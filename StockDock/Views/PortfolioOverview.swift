import SwiftUI
import Charts

/// A holding priced in the preferred currency, with the derived figures the
/// overview needs.
struct ValuedHolding: Identifiable {
    let id: UUID
    let portfolioId: UUID
    let holding: Holding
    let quote: StockQuote
    let value: Double
    let cost: Double
    let dayChangePercent: Double
    let type: String

    var symbol: String { holding.symbol }
    var name: String { quote.name.isEmpty ? holding.symbol : quote.name }
    var pnl: Double { value - cost }
    var pnlPercent: Double { abs(cost) >= 0.01 ? (pnl / abs(cost)) * 100 : 0 }
}

struct PortfolioOverview: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.editHoldingAction) private var editHoldingAction
    @Environment(\.addHoldingAction) private var addHoldingAction
    @Environment(\.portfolioActions) private var portfolioActions
    let scope: PortfolioWindowView.Scope

    /// Hero chart range — a pure UI filter over the value series.
    enum ChartRange: String, CaseIterable {
        case day = "24H", week = "7D", month = "1M", year = "1Y", all = "All"
        var days: Int? {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return nil
            }
        }
        /// Suffix for the hero pill, describing the span it measures.
        var changeLabel: String {
            switch self {
            case .day: return "today"
            case .week: return "past 7d"
            case .month: return "past 1M"
            case .year: return "past 1Y"
            case .all: return "all-time"
            }
        }
    }
    /// #14: seeded from the last range the user picked (see `restoreRange`), so
    /// the chart opens where they left it instead of always on All.
    @State private var chartRange: ChartRange = .all
    /// Applies the remembered range, if there is a valid one stored.
    private func restoreRange() {
        if let saved = ChartRange(rawValue: storageService.lastPortfolioChartRange) {
            chartRange = saved
        }
    }

    @State private var hoveredSlice: String?
    @State private var hoverPoint: ValuePoint?

    /// Tooltip date label — time for intraday ranges, date for the rest.
    private func tooltipDate(_ date: Date) -> String {
        switch chartRange {
        case .day: return date.formatted(.dateTime.hour().minute())
        case .week: return date.formatted(.dateTime.weekday(.abbreviated).hour())
        default: return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private var portfolios: [Portfolio] {
        switch scope {
        // #14: the combined view shows only what counts toward the total; opening
        // an excluded portfolio directly still shows it in full.
        case .all: return storageService.countedPortfolios
        case .portfolio(let id): return storageService.portfolios.filter { $0.id == id }
        }
    }

    private var title: String {
        switch scope {
        case .all: return "Portfolio"
        case .portfolio(let id): return storageService.portfolios.first { $0.id == id }?.name ?? "Portfolio"
        }
    }

    private var currencySymbol: String { StorageService.currencySymbol(for: storageService.preferredCurrency) }
    private var decimals: Int { storageService.percentDecimals }

    /// Everything derived from positions × quotes, computed ONCE per render.
    ///
    /// These used to be computed properties. Each read re-ran the whole
    /// flatMap/compactMap/sort — and `body` reads them roughly a dozen times
    /// (caption, hero, stat row, allocation, movers, type strip, positions).
    /// At 60fps that was a dozen full re-valuations per frame; `holdings` was
    /// the single hottest symbol of our own code in the CPU profile.
    private struct Derived {
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

    private var derived: Derived {
        var d = Derived()
        d.holdings = portfolios.flatMap { portfolio in
            portfolio.holdings.compactMap { holding -> ValuedHolding? in
                guard let quote = stockService.quotes[holding.symbol] else { return nil }
                let price = quote.displayPrice(extendedHours: storageService.showExtendedHours)
                let value = holding.marketValue(currentPrice: price) * stockService.rate(from: quote.currency)
                let cost = holding.costBasisLocal * stockService.rate(from: quote.currency, for: holding.purchaseDate)
                return ValuedHolding(id: holding.id, portfolioId: portfolio.id, holding: holding, quote: quote,
                                     value: value, cost: cost, dayChangePercent: quote.changePercent,
                                     type: storageService.type(for: holding.symbol))
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
    private func displaySeries(totalValue: Double) -> (points: [ValuePoint], isEstimated: Bool) {
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

    private var symbols: [String] { Array(Set(portfolios.flatMap { $0.holdings.map(\.symbol) })) }

    var body: some View {
        // Valued ONCE per render, then threaded into every section (see `Derived`).
        let d = derived
        return PageScaffold(title, caption: "\(d.holdings.count) positions · \(storageService.preferredCurrency)") {
            HStack(spacing: 12) {
                portfolioMenu
                RefreshButton(isLoading: stockService.isLoading) {
                    Task { await stockService.refreshAll(storageService: storageService) }
                }
            }
        } content: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.gap) {
                        heroCard(d)
                        statRow(d)
                        HStack(alignment: .top, spacing: DS.gap) {
                            allocationCard(d).frame(maxWidth: .infinity)
                            moversCard(proxy: proxy, d).frame(width: 340)
                        }
                        positionsCard(d).id("positions")
                    }
                    .pageColumn()
                    .padding(.top, 4)
                }
            }
        }
        .navigationTitle(title)
        .task(id: symbols) {
            for symbol in symbols { await stockService.ensurePriceHistory(for: symbol) }
        }
        .task(id: "\(symbols.joined())-\(chartRange.rawValue)") {
            switch chartRange {
            case .day: for s in symbols { await stockService.ensureIntraday(for: s) }
            case .week: for s in symbols { await stockService.ensureIntradayWeek(for: s) }
            case .all: for s in symbols { await stockService.ensurePriceHistoryMax(for: s) }
            default: break
            }
        }
    }

    // MARK: - Hero (chart as the ground of the card)

    private func heroCard(_ d: Derived) -> some View {
        // Compute the (expensive) value series ONCE per render — it was being
        // recomputed 5× (badge, picker, chart points, chart dash), which showed
        // up as lag when switching portfolios (each switch rebuilds this view).
        let ds = displaySeries(totalValue: d.totalValue)
        // Pill reflects the SELECTED range: change across the drawn curve. When
        // the curve is too sparse to span a period (e.g. day one), fall back to
        // the day-over-day figure so the pill is never empty.
        //
        // 24H → the real "today" (extended-hours-aware day change), so the pill
        // matches the TODAY stat exactly and reflects the same price basis as the
        // value (incl. any pre/post-market move). All → the real all-time P&L, not
        // the reconstructed-curve span (which starts near €0 and reads a bogus
        // "+2202%"). 7D/1M/1Y → the curve span over that bounded window.
        let useRealDay = chartRange == .day
        let useRealAllTime = chartRange == .all
        let periodValue = useRealDay ? d.dayChangeValue
            : useRealAllTime ? d.totalPnl
            : (PortfolioPeriodChange.value(ds.points) ?? d.dayChangeValue)
        let periodPercent = useRealDay ? d.dayChangePercent
            : useRealAllTime ? d.totalPnlPercent
            : (PortfolioPeriodChange.percent(ds.points) ?? d.dayChangePercent)
        let periodLabel = useRealDay ? "today"
            : useRealAllTime ? "all-time"
            : (PortfolioPeriodChange.percent(ds.points) != nil ? chartRange.changeLabel : "today")
        // Header sits ABOVE the chart (not over it) so the curve can never rise
        // behind the value/pill text — on 24H the peak often lands top-left, right
        // where the text is, and no Y-domain trick can avoid that overlap.
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    SectionLabel("\(title) value")
                    Spacer()
                    HStack(spacing: 10) {
                        if ds.isEstimated, !ds.points.isEmpty {
                            Text("ESTIMATED")
                                .font(.inter(8.5, weight: .bold, relativeTo: .caption2)).tracking(0.8)
                                .foregroundStyle(DS.gold)
                                .help("Reconstructed from price history × current positions. Real daily tracking replaces it over time.")
                        }
                        // No picker over an empty chart — it appears with the data.
                        if !ds.points.isEmpty { rangePicker }
                    }
                }
                Text(StorageService.formatAmount(d.totalValue, symbol: currencySymbol, decimals: storageService.amountDecimals))
                    .font(DS.display).tracking(-0.5)
                    .foregroundStyle(DS.ink)
                    .contentTransition(.numericText())
                    // Price-driven: must settle between 1s tick flushes (see DS.tick).
                    .animation(DS.tick, value: d.totalValue)
                HStack(spacing: 10) {
                    ChangePill(value: periodValue,
                               text: String(format: "%+.\(decimals)f%% %@", periodPercent, periodLabel))
                    // The all-time figure alongside — hidden on the All range,
                    // where the pill already shows exactly this (no duplicate).
                    if !useRealAllTime {
                        Text(String(format: "%@ (%+.\(decimals)f%%) all-time",
                                    StorageService.formatAmount(d.totalPnl, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                                    d.totalPnlPercent))
                            .font(DS.caption.monospacedDigit())
                            .foregroundStyle(DS.pnlColor(d.totalPnl))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            heroChart(ds)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .premiumCard()
    }

    private var rangePicker: some View {
        SegmentedRangePicker(options: ChartRange.allCases, label: \.rawValue, selection: $chartRange)
            .onAppear(perform: restoreRange)
            .onChange(of: chartRange) { _, new in
                storageService.lastPortfolioChartRange = new.rawValue
            }
    }

    /// The same actions as the sidebar right-click, as a header "⋯" menu — shown
    /// only when viewing a single portfolio.
    @ViewBuilder private var portfolioMenu: some View {
        if case .portfolio(let id) = scope, let p = portfolios.first {
            DSMenu(sections: [
                [ DSMenuAction(title: "Add Holding…", icon: "plus") { portfolioActions.addHolding(id) },
                  DSMenuAction(title: "Rename…", icon: "pencil") { portfolioActions.rename(id, p.name) },
                  DSMenuAction(title: "Notifications…", icon: "bell") { portfolioActions.notifications(id, p.name) },
                  DSMenuAction(title: "Export…", icon: "square.and.arrow.up") { portfolioActions.export(p) } ],
                [ DSMenuAction(title: "Delete Portfolio", icon: "trash", destructive: true) { portfolioActions.delete(id) } ],
            ]) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DS.cardAlt))
            }
            .help("Portfolio actions — add holding, rename, notifications, export, delete")
        }
    }

    /// Y domain with a little headroom so the line never touches the card edges.
    private func valueDomain(_ points: [ValuePoint]) -> ClosedRange<Double> {
        let vals = points.map(\.value)
        guard let lo = vals.min(), let hi = vals.max(), hi > lo else { return 0...1 }
        let span = hi - lo
        return (lo - span * 0.10)...(hi + span * 0.14)
    }

    /// X-axis tick label formatted for the selected period.
    /// `span` is the drawn curve's own duration: since the estimate now starts at the
    /// oldest purchase, "All" can cover a single month, where four "lug 2026" ticks
    /// say nothing. Under a year it falls back to day+month.
    private func xAxisLabel(_ date: Date, span: TimeInterval) -> String {
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

    /// Smooth hover crosshair drawn as an overlay (not chart marks).
    @ViewBuilder private func valueCrosshair(_ proxy: ChartProxy, points: [ValuePoint], tint: Color) -> some View {
        GeometryReader { geo in
            if let plotAnchor = proxy.plotFrame {
                let plot = geo[plotAnchor]
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                // Clamp inside the plot so edges still resolve a value.
                                let localX = min(max(loc.x - plot.minX, 0), plot.width)
                                if let d: Date = proxy.value(atX: localX) {
                                    hoverPoint = nearestByDate(points, to: d, date: \.date)
                                }
                            case .ended:
                                hoverPoint = nil
                            }
                        }
                    if let h = hoverPoint,
                       let px = proxy.position(forX: h.date),
                       let py = proxy.position(forY: h.value) {
                        let cx = plot.minX + px
                        Group {
                            Path { p in p.move(to: CGPoint(x: cx, y: plot.minY)); p.addLine(to: CGPoint(x: cx, y: plot.maxY)) }
                                .stroke(DS.inkTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            Circle().fill(tint).frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .position(x: cx, y: plot.minY + py)
                            ChartTooltip(title: tooltipDate(h.date),
                                         value: StorageService.formatAmount(h.value, symbol: currencySymbol, decimals: storageService.amountDecimals),
                                         tint: tint)
                                .position(x: min(max(cx, plot.minX + 46), plot.maxX - 46), y: plot.minY + 8)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    @ViewBuilder private func heroChart(_ ds: (points: [ValuePoint], isEstimated: Bool)) -> some View {
        let points = ds.points
        if points.count >= 2 {
            // Consistent color across periods: emerald when the period is up,
            // terracotta when down. Estimated state is shown by the dash only.
            let periodUp = (points.last?.value ?? 0) >= (points.first?.value ?? 0)
            let tint = periodUp ? DS.up : DS.down
            let span = (points.last?.date.timeIntervalSince(points.first?.date ?? .distantPast)) ?? 0
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Day", p.date), y: .value("Value", p.value))
                        .foregroundStyle(.linearGradient(colors: [tint.opacity(0.22), tint.opacity(0)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                        .foregroundStyle(tint).lineStyle(.init(lineWidth: 2, dash: ds.isEstimated ? [4, 3] : []))
                        .interpolationMethod(.monotone)
                }
                if let last = points.last {
                    PointMark(x: .value("Day", last.date), y: .value("Value", last.value))
                        .symbolSize(50)
                        .foregroundStyle(tint)
                }
            }
            .chartYScale(domain: valueDomain(points))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(DS.chartGrid)
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(StorageService.formatAmount(d, symbol: currencySymbol, decimals: 0))
                                .font(DS.micro).foregroundStyle(DS.inkTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(DS.chartGrid)
                    if let d = value.as(Date.self) {
                        AxisValueLabel { Text(xAxisLabel(d, span: span)).font(DS.micro).foregroundStyle(DS.inkTertiary) }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in valueCrosshair(proxy, points: points, tint: tint) }
            // Morph marks in place when async data lands (avoids a hard "pop" as
            // intraday/history loads after a range switch).
            //
            // Keyed on the point COUNT, not the array: on the 24H range the last
            // point is re-pinned to the live total every tick (see displaySeries),
            // so `value: points` re-ran a 0.4s animation of every mark once a
            // second — and compared the whole array on every render besides. The
            // count still changes exactly when new bars arrive, which is the case
            // this animation exists for.
            .animation(.easeInOut(duration: 0.4), value: points.count)
            // Range switch replaces the chart; crossfade it rather than cut.
            .id(chartRange)
            .transition(.opacity.animation(.easeInOut(duration: 0.4)))
        } else {
            ZStack {
                DS.cardAlt.opacity(0.6)
                DecorativeCurve()
                    .stroke(DS.hairline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .padding(.horizontal, 24)
                VStack(spacing: 4) {
                    Text("Value history builds up day by day")
                        .font(.inter(11, weight: .medium, relativeTo: .caption)).foregroundStyle(DS.inkSecondary)
                    Text("Your first trend appears tomorrow.")
                        .font(DS.micro).foregroundStyle(DS.inkTertiary)
                }
            }
        }
    }

    // MARK: - Stats

    private func statRow(_ d: Derived) -> some View {
        HStack(spacing: 12) {
            StatTile(label: "Total P&L",
                     value: StorageService.formatAmount(d.totalPnl, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                     caption: String(format: "%+.\(decimals)f%% on cost", d.totalPnlPercent),
                     captionTint: DS.pnlColor(d.totalPnl), valueTint: DS.pnlColor(d.totalPnl),
                     help: "Total profit/loss vs your cost basis")
            StatTile(label: "Today",
                     value: StorageService.formatAmount(d.dayChangeValue, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                     caption: String(format: "%+.\(decimals)f%%", d.dayChangePercent),
                     captionTint: DS.pnlColor(d.dayChangeValue), valueTint: DS.pnlColor(d.dayChangeValue),
                     help: "Change since the previous close")
            StatTile(label: "Invested",
                     value: StorageService.formatAmount(d.totalCost, symbol: currencySymbol, decimals: storageService.amountDecimals),
                     caption: "\(d.holdings.count) holdings",
                     help: "Total amount invested (cost basis)")
            StatTile(label: "Concentration",
                     value: String(format: "%.1f%%", d.topWeight),
                     caption: d.topSymbol.map { d.topWeight > 40 ? "high · top \($0)" : "top · \($0)" } ?? "—",
                     captionTint: d.topWeight > 40 ? DS.gold : DS.inkTertiary,
                     help: "Weight of your largest position — a diversification risk gauge")
        }
    }

    // MARK: - Allocation (donut + legend + type strip)

    private struct AllocationSlice: Identifiable {
        let id: String
        let symbol: String
        let value: Double
        let fraction: Double
    }
    private func allocationCard(_ d: Derived) -> some View {
        Card(title: "Allocation") {
            if d.allocation.isEmpty {
                emptyLine
            } else {
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        ZStack {
                            Chart(d.allocation) { slice in
                                SectorMark(angle: .value("Value", slice.value),
                                           innerRadius: .ratio(0.64), angularInset: 2)
                                    .cornerRadius(3)
                                    .foregroundStyle(d.color(for: slice.symbol))
                                    .opacity(hoveredSlice == nil || hoveredSlice == slice.symbol ? 1 : 0.35)
                            }
                            .chartLegend(.hidden)
                            VStack(spacing: 1) {
                                Text("\(d.allocation.count)").font(DS.figureLG).foregroundStyle(DS.ink)
                                SectionLabel("Assets")
                            }
                        }
                        .frame(width: 136, height: 136)

                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(d.allocation.prefix(6)) { slice in
                                HStack(spacing: 9) {
                                    RoundedRectangle(cornerRadius: 2.5).fill(d.color(for: slice.symbol)).frame(width: 9, height: 9)
                                    Text(slice.symbol).font(DS.figure).foregroundStyle(DS.ink)
                                    Spacer()
                                    Text(String(format: "%.1f%%", slice.fraction * 100))
                                        .font(DS.figure).foregroundStyle(DS.inkSecondary)
                                }
                                .contentShape(Rectangle())
                                .onHover { hoveredSlice = $0 ? slice.symbol : nil }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !d.typeBreakdown.isEmpty {
                        Divider().overlay(DS.hairline)
                        typeStrip(d)
                    }
                }
            }
        }
    }

    private func typeStrip(_ d: Derived) -> some View {
        let typeBreakdown = d.typeBreakdown
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(typeBreakdown.enumerated()), id: \.element.label) { idx, row in
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(DS.palette[idx % DS.palette.count])
                            .frame(width: max(2, geo.size.width * row.fraction - 2))
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                ForEach(Array(typeBreakdown.enumerated()), id: \.element.label) { idx, row in
                    HStack(spacing: 5) {
                        Circle().fill(DS.palette[idx % DS.palette.count]).frame(width: 6, height: 6)
                        Text(row.label).font(DS.caption).foregroundStyle(DS.inkSecondary)
                        Text(String(format: "%.0f%%", row.fraction * 100))
                            .font(DS.caption.monospacedDigit()).foregroundStyle(DS.inkTertiary)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Movers

    private func moversCard(proxy: ScrollViewProxy, _ d: Derived) -> some View {
        Card(title: "Today's movers") {
            var seen = Set<String>()
            let movers = d.holdings.filter { seen.insert($0.symbol).inserted }
                .sorted { abs($0.dayChangePercent) > abs($1.dayChangePercent) }
            let maxAbs = movers.map { abs($0.dayChangePercent) }.max() ?? 1
            if movers.isEmpty {
                emptyLine
            } else {
                VStack(spacing: 0) {
                    ForEach(movers.prefix(5)) { h in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DS.brand.opacity(0.10))
                                .frame(width: 24, height: 24)
                                .overlay(Text(h.symbol.prefix(1))
                                    .font(DS.micro).foregroundStyle(DS.brand))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.symbol).font(DS.figure).foregroundStyle(DS.ink)
                                Text(h.name).font(DS.micro).foregroundStyle(DS.inkTertiary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "%+.\(decimals)f%%", h.dayChangePercent))
                                    .font(.inter(12, weight: .semibold, relativeTo: .body).monospacedDigit())
                                    .foregroundStyle(DS.pnlColor(h.dayChangePercent))
                                ZStack(alignment: h.dayChangePercent >= 0 ? .leading : .trailing) {
                                    Capsule().fill(DS.cardAlt).frame(width: 48, height: 4)
                                    Capsule().fill(DS.pnlColor(h.dayChangePercent))
                                        .frame(width: max(4, 48 * abs(h.dayChangePercent) / max(maxAbs, 0.01)), height: 4)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        if h.id != movers.prefix(5).last?.id {
                            Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                        }
                    }
                    if d.holdings.count > 5 {
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("positions", anchor: .top) }
                        } label: {
                            Text("View all positions ↓")
                                .font(.inter(10.5, weight: .medium, relativeTo: .caption2))
                                .foregroundStyle(DS.brand)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                }
            }
        }
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

    // MARK: - Positions

    private func positionsCard(_ d: Derived) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionLabel("Positions")
                Spacer()
                addHoldingButton
            }
            if d.holdings.isEmpty {
                VStack(spacing: 10) {
                    Text("No holdings yet").font(DS.bodyStrong).foregroundStyle(DS.ink)
                    Text("Add your first position to start tracking value and P&L.")
                        .font(DS.caption).foregroundStyle(DS.inkSecondary)
                    addHoldingButton
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Symbol").frame(width: 168, alignment: .leading)
                        Text("Last").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Change").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Value").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("P&L").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Weight").frame(width: 110, alignment: .trailing)
                        Color.clear.frame(width: 16)
                    }
                    .font(DS.label)
                    .foregroundStyle(DS.inkTertiary)
                    .tracking(0.8).textCase(.uppercase)
                    .padding(.bottom, 12)
                    Divider().overlay(DS.hairline)
                    ForEach(d.holdings) { h in
                        NavigationLink(value: h.id) {
                            PositionRow(h: h, currencySymbol: currencySymbol,
                                        weight: abs(d.totalValue) >= 0.01 ? abs(h.value) / abs(d.totalValue) * 100 : 0,
                                        topWeight: d.topWeight,
                                        decimals: decimals,
                                        valueDecimals: storageService.valueDecimals,
                                        percentDecimals: storageService.percentDecimals)
                        }
                        .buttonStyle(.plain)
                        .help("View \(h.symbol) details · right-click to edit or delete")
                        .contextMenu {
                            Button { editHoldingAction.perform(h.portfolioId, h.holding) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) {
                                storageService.removeHolding(from: h.portfolioId, holdingId: h.holding.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        if h.id != d.holdings.last?.id {
                            Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let h = d.holdings.first(where: { $0.id == id }) {
                        HoldingDetailView(portfolioId: h.portfolioId, holding: h.holding, quote: h.quote,
                                          value: h.value, cost: h.cost,
                                          weight: abs(d.totalValue) >= 0.01 ? abs(h.value) / abs(d.totalValue) * 100 : 0)
                    }
                }
            }
        }
        .padding(DS.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard()
    }

    /// Visible "+ Add holding" affordance. Adds directly to the focused portfolio;
    /// on "All Portfolios" it picks the one portfolio, or offers a menu to choose.
    @ViewBuilder private var addHoldingButton: some View {
        let label = HStack(spacing: 4) {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
            Text("Add holding").font(.inter(11, weight: .semibold, relativeTo: .caption))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Capsule().fill(DS.brand))

        switch scope {
        case .portfolio(let id):
            Button { addHoldingAction.perform(id) } label: { label }.buttonStyle(.plain)
                .help("Add a holding to this portfolio")
        case .all:
            if storageService.portfolios.count == 1, let id = storageService.portfolios.first?.id {
                Button { addHoldingAction.perform(id) } label: { label }.buttonStyle(.plain)
                    .help("Add a holding")
            } else if !storageService.portfolios.isEmpty {
                Menu {
                    ForEach(storageService.portfolios) { p in
                        Button(p.name) { addHoldingAction.perform(p.id) }
                    }
                } label: { label }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Add a holding — choose which portfolio")
            }
        }
    }

    private var emptyLine: some View {
        Text("No holdings yet").font(DS.caption).foregroundStyle(DS.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
    }
}

// MARK: - Position row

private struct PositionRow: View {
    let h: ValuedHolding
    let currencySymbol: String
    let weight: Double
    let topWeight: Double
    let decimals: Int
    let valueDecimals: Int
    let percentDecimals: Int
    @State private var hovered = false

    private var amountDec: Int { valueDecimals >= 0 ? valueDecimals : 2 }
    private func priceDec(_ price: Double) -> Int {
        valueDecimals >= 0 ? valueDecimals : StorageService.priceDecimals(symbol: h.symbol, price: price)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DS.brand.opacity(0.10))
                    .frame(width: 30, height: 30)
                    .overlay(Text(h.symbol.prefix(2))
                        .font(.inter(10, weight: .bold, relativeTo: .caption2))
                        .foregroundStyle(DS.brand))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(h.symbol).font(DS.figure).foregroundStyle(DS.ink)
                        if h.holding.isShort { Tag(text: "S", color: DS.down) }
                    }
                    // #14: the share count belongs on the row people actually look
                    // at — until now it only existed in the compact list and the
                    // holding detail. Shares lead; the name fills what's left.
                    Text("\(StorageService.formatQuantity(h.holding.quantity)) sh · \(h.name)")
                        .font(DS.micro).foregroundStyle(DS.inkTertiary).lineLimit(1)
                }
            }
            .frame(width: 168, alignment: .leading)

            Text(StorageService.formatAmount(h.quote.displayPrice(extendedHours: false), symbol: currencySymbol, decimals: priceDec(h.quote.displayPrice(extendedHours: false))))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .font(DS.figure).foregroundStyle(DS.ink)
                .contentTransition(.numericText())
            VStack(alignment: .trailing, spacing: 1) {
                ChangePill(value: h.quote.change,
                           text: StorageService.formatAmount(h.quote.change, symbol: "", decimals: priceDec(h.quote.change), signed: true, truncateZeros: true))
                Text(String(format: "%+.\(percentDecimals)f%%", h.quote.changePercent))
                    .font(DS.micro)
            }
            .foregroundStyle(DS.pnlColor(h.quote.change))
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text(StorageService.formatAmount(h.value, symbol: currencySymbol, decimals: amountDec))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .font(DS.figure).foregroundStyle(DS.ink)
                .contentTransition(.numericText())
            VStack(alignment: .trailing, spacing: 1) {
                Text(StorageService.formatAmount(h.pnl, symbol: currencySymbol, decimals: amountDec, signed: true))
                    .font(DS.figure)
                    .contentTransition(.numericText())
                Text(String(format: "%+.\(decimals)f%%", h.pnlPercent))
                    .font(DS.micro)
            }
            .foregroundStyle(DS.pnlColor(h.pnl))
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Weight: the signature bar + figure.
            HStack(spacing: 7) {
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.cardAlt).frame(width: 56, height: 3)
                    Capsule().fill(DS.brand.opacity(0.5))
                        .frame(width: max(2, 56 * weight / max(topWeight, 0.01)), height: 3)
                }
                Text(String(format: "%.1f%%", weight))
                    .font(.inter(11, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(DS.inkSecondary)
            }
            .frame(width: 110, alignment: .trailing)

            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hovered ? DS.brand : DS.inkTertiary)
                .frame(width: 16)
        }
        .padding(.vertical, 9).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovered ? DS.cardAlt : .clear))
        .animation(.easeOut(duration: 0.15), value: hovered)
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
