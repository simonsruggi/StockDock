import SwiftUI

extension PortfolioOverviewView {
    /// Tooltip date label — time for intraday ranges, date for the rest.
    func tooltipDate(_ date: Date) -> String {
        switch chartRange {
        case .day: return date.formatted(.dateTime.hour().minute())
        case .week: return date.formatted(.dateTime.weekday(.abbreviated).hour())
        default: return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
    /// Everything derived from positions × quotes, computed ONCE per render.
    ///
    /// These used to be computed properties. Each read re-ran the whole
    /// flatMap/compactMap/sort — and `body` reads them roughly a dozen times
    /// (caption, hero, stat row, allocation, movers, type strip, positions).
    /// At 60fps that was a dozen full re-valuations per frame; `holdings` was
    /// the single hottest symbol of our own code in the CPU profile.
    struct Derived {
        var holdings: [ValuedHolding] = []
        var totalValue: Double = 0
        var totalCost: Double = 0
        var dayChangeValue: Double = 0
        var allocation: [AllocationSlice] = []
        var typeBreakdown: [(label: String, fraction: Double)] = []

        var totalPnl: Double { totalValue - totalCost }
        var totalPnlPercent: Double { abs(totalCost) >= 0.01 ? (totalPnl / abs(totalCost)) * 100 : 0 }
        var dayChangePercent: Double {
            let base = totalValue - dayChangeValue
            return abs(base) >= 0.01 ? (dayChangeValue / abs(base)) * 100 : 0
        }
        var topSymbol: String? { allocation.first?.symbol }
        var topWeight: Double { (allocation.first?.fraction ?? 0) * 100 }

        func color(for symbol: String) -> Color {
            let idx = allocation.firstIndex { $0.symbol == symbol } ?? 0
            return DS.palette[idx % DS.palette.count]
        }
    }

    var derived: Derived {
        var d = Derived()
        d.holdings = portfolios.flatMap { portfolio in
            portfolio.holdings.compactMap { holding -> ValuedHolding? in
                guard let quote = stockService.quotes[holding.symbol] else { return nil }
                let price = quote.displayPrice(extendedHours: storageService.showExtendedHours)
                let value = holding.marketValue(currentPrice: price) * stockService.rate(from: quote.currency)
                let cost = holding.costBasisLocal * stockService.rate(from: quote.currency, for: holding.purchaseDate)
                let priced = stockService.priceDisplay(for: quote.currency)
                return ValuedHolding(id: holding.id, portfolioId: portfolio.id, holding: holding, quote: quote,
                                     value: value, cost: cost, dayChangePercent: quote.changePercent,
                                     type: storageService.type(for: holding.symbol),
                                     priceRate: priced.rate, priceCurrency: priced.currency)
            }
        }
        .sorted { abs($0.value) > abs($1.value) }

        var absTotal: Double = 0
        var bySymbol: [String: Double] = [:]
        var byType: [String: Double] = [:]
        for h in d.holdings {
            d.totalValue += h.value
            d.totalCost += h.cost
            // Use the change consistent with the price the value is computed at
            // (extended-hours-aware), so TODAY can't disagree in sign with the value.
            let change = h.quote.effectiveChange(extendedHours: storageService.showExtendedHours)
            d.dayChangeValue += h.holding.dailyPnl(priceChange: change) * stockService.rate(from: h.quote.currency)

            let weight = abs(h.value)
            absTotal += weight
            bySymbol[h.symbol, default: 0] += weight
            byType[Self.typeLabel(h.type), default: 0] += weight
        }

        if absTotal >= 0.01 {
            d.allocation = bySymbol
                .map { AllocationSlice(id: $0.key, symbol: $0.key, value: $0.value, fraction: $0.value / absTotal) }
                .sorted { $0.value > $1.value }
            d.typeBreakdown = byType.map { ($0.key, $0.value / absTotal) }.sorted { $0.1 > $1.1 }
        }
        return d
    }

    /// Snapshot series for the scope, merged by day when aggregating portfolios.
    private var series: [PortfolioSnapshot] {
        let logs = portfolios.map { storageService.snapshots(for: $0.id) }
        guard logs.contains(where: { !$0.isEmpty }) else { return [] }
        if logs.count == 1 { return logs[0] }
        var byDay: [Date: (value: Double, cost: Double)] = [:]
        for log in logs { for snap in log {
            byDay[snap.date, default: (0, 0)].value += snap.totalValue
            byDay[snap.date, default: (0, 0)].cost += snap.totalCost
        } }
        return byDay.map { PortfolioSnapshot(date: $0.key, totalValue: $0.value.value, totalCost: $0.value.cost) }
            .sorted { $0.date < $1.date }
    }

    private var filteredSeries: [PortfolioSnapshot] {
        guard let days = chartRange.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return series }
        return series.filter { $0.date >= cutoff }
    }

    /// Builds an estimated value curve from a given per-symbol price history
    /// (daily / hourly / 5-min) × current positions, in the preferred currency.
    private func valueSeries(from histBySymbol: [String: [PricePoint]]) -> [ValuePoint] {
        let hs = portfolios.flatMap { $0.holdings }
        var rate: [String: Double] = [:]
        var hist: [String: [PricePoint]] = [:]
        for h in hs {
            if let q = stockService.quotes[h.symbol] { rate[h.symbol] = stockService.rate(from: q.currency) }
            if let ph = histBySymbol[h.symbol] { hist[h.symbol] = ph }
        }
        return PortfolioBackfill.series(holdings: hs, historyBySymbol: hist, rateBySymbol: rate)
    }

    /// Oldest purchase across the shown portfolios — where the estimated curve
    /// starts (nil when no holding records a date, i.e. legacy/imported lots).
    private var ownedSince: Date? {
        portfolios.flatMap { $0.holdings }.compactMap(\.purchaseDate).min()
    }

    /// Daily estimate (2y) for 1M/1Y. "All" needs the monthly max-history only when
    /// the portfolio actually predates the daily window — since the curve now starts
    /// at the oldest purchase, a portfolio built this year would otherwise be drawn
    /// as a handful of monthly steps.
    private var estimatedSeries: [ValuePoint] {
        guard chartRange == .all else { return valueSeries(from: stockService.priceHistory) }
        let dailyStart = Calendar.current.date(byAdding: .year, value: -2, to: Date())
        if let since = ownedSince, let dailyStart, since >= dailyStart {
            return valueSeries(from: stockService.priceHistory)
        }
        return valueSeries(from: stockService.priceHistoryMax)
    }
    private var estimatedFiltered: [ValuePoint] {
        guard let days = chartRange.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return estimatedSeries }
        return estimatedSeries.filter { $0.date >= cutoff }
    }

    /// The curve actually drawn. 24H/7D use intraday-estimated value (the daily
    /// snapshots have no intraday resolution); 1M+ prefer real snapshots once
    /// they're as dense as the daily estimate. `isEstimated` drives the badge.
    func displaySeries(totalValue: Double) -> (points: [ValuePoint], isEstimated: Bool) {
        switch chartRange {
        case .day:
            // Intraday value path. The reconstructed bars can lag the live quote
            // (and omit the pre/post-market move), so pin the final point to the
            // real current value — otherwise the curve ends below the headline
            // total (e.g. €52.5k vs €55.2k) and understates the day.
            var pts = valueSeries(from: stockService.intradayHistory)
            if let last = pts.last, abs(last.value - totalValue) > 0.01 {
                pts.append(ValuePoint(date: last.date.addingTimeInterval(1), value: totalValue))
            }
            return (pts, true)
        case .week:
            return (valueSeries(from: stockService.intradayWeek), true)
        default:
            let real = filteredSeries.map { ValuePoint(date: $0.date, value: $0.totalValue) }
            let est = estimatedFiltered
            if real.count >= 2 && real.count >= est.count { return (real, false) }
            if est.count >= 2 { return (est, true) }
            return (real, false)
        }
    }
    /// Y domain with a little headroom so the line never touches the card edges.
    func valueDomain(_ points: [ValuePoint]) -> ClosedRange<Double> {
        let vals = points.map(\.value)
        guard let lo = vals.min(), let hi = vals.max(), hi > lo else { return 0...1 }
        let span = hi - lo
        return (lo - span * 0.10)...(hi + span * 0.14)
    }

    /// X-axis tick label formatted for the selected period.
    /// `span` is the drawn curve's own duration: since the estimate now starts at the
    /// oldest purchase, "All" can cover a single month, where four "lug 2026" ticks
    /// say nothing. Under a year it falls back to day+month.
    func xAxisLabel(_ date: Date, span: TimeInterval) -> String {
        switch chartRange {
        case .day: return date.formatted(.dateTime.hour().minute())
        case .week: return date.formatted(.dateTime.weekday(.abbreviated))
        case .month: return date.formatted(.dateTime.day().month(.abbreviated))
        case .year, .all:
            guard span >= 365 * 86400 else { return date.formatted(.dateTime.day().month(.abbreviated)) }
            // Four-digit year: "gen 05" reads as the 5th of January, not January 2005.
            return date.formatted(.dateTime.month(.abbreviated).year())
        }
    }
    struct AllocationSlice: Identifiable {
        let id: String
        let symbol: String
        let value: Double
        let fraction: Double
    }
    // MARK: - Diversification data

    private static func typeLabel(_ type: String) -> String {
        switch type.uppercased() {
        case "EQUITY": return "Stocks"
        case "ETF": return "ETFs"
        case "CRYPTOCURRENCY": return "Crypto"
        case "INDEX": return "Indices"
        case "FUTURE": return "Futures"
        case "MUTUALFUND": return "Funds"
        case "CURRENCY": return "Currency"
        case "": return "Other"
        default: return type.capitalized
        }
    }
}
