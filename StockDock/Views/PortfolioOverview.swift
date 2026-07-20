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
    @State private var chartRange: ChartRange = .all
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
        case .all: return storageService.portfolios
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

    private var holdings: [ValuedHolding] {
        portfolios.flatMap { portfolio in
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
    }

    private var totalValue: Double { holdings.reduce(0) { $0 + $1.value } }
    private var totalCost: Double { holdings.reduce(0) { $0 + $1.cost } }
    private var totalPnl: Double { totalValue - totalCost }
    private var totalPnlPercent: Double { abs(totalCost) >= 0.01 ? (totalPnl / abs(totalCost)) * 100 : 0 }

    private var dayChangeValue: Double {
        holdings.reduce(0) { sum, h in
            sum + h.quote.change * h.holding.quantity * h.holding.effectiveLeverage * stockService.rate(from: h.quote.currency)
        }
    }
    private var dayChangePercent: Double {
        let base = totalValue - dayChangeValue
        return abs(base) >= 0.01 ? (dayChangeValue / abs(base)) * 100 : 0
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

    /// Daily estimate (2y) for 1M/1Y; monthly full history for "All".
    private var estimatedSeries: [ValuePoint] {
        valueSeries(from: chartRange == .all ? stockService.priceHistoryMax : stockService.priceHistory)
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
    private var displaySeries: (points: [ValuePoint], isEstimated: Bool) {
        switch chartRange {
        case .day:
            return (valueSeries(from: stockService.intradayHistory), true)
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
        PageScaffold(title, caption: "\(holdings.count) positions · \(storageService.preferredCurrency)") {
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
                        heroCard
                        statRow
                        HStack(alignment: .top, spacing: DS.gap) {
                            allocationCard.frame(maxWidth: .infinity)
                            moversCard(proxy: proxy).frame(width: 340)
                        }
                        positionsCard.id("positions")
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

    private var heroCard: some View {
        // Compute the (expensive) value series ONCE per render — it was being
        // recomputed 5× (badge, picker, chart points, chart dash), which showed
        // up as lag when switching portfolios (each switch rebuilds this view).
        let ds = displaySeries
        // Pill reflects the SELECTED range: change across the drawn curve. When
        // the curve is too sparse to span a period (e.g. day one), fall back to
        // the day-over-day figure so the pill is never empty.
        //
        // EXCEPTIONS — the pill must never show the span of the ESTIMATED curve
        // as a real return:
        //  • 24H → the real regular-session day change (same as the TODAY stat).
        //    The curve span starts at the intraday low, not the previous close,
        //    so it could read "+4.0% today" while the day is actually down.
        //  • All → the real all-time P&L (current value vs cost basis). The "All"
        //    curve starts at the reconstruction origin (current positions at old,
        //    tiny prices), so its span is a huge bogus "+2202% all-time" instead
        //    of the actual return.
        // Bounded windows (7D/1M/1Y) keep the curve span — there's no better
        // figure and the "past N" label makes the estimate honest.
        let useRealDay = chartRange == .day
        let useRealAllTime = chartRange == .all
        let periodValue = useRealDay ? dayChangeValue
            : useRealAllTime ? totalPnl
            : (PortfolioPeriodChange.value(ds.points) ?? dayChangeValue)
        let periodPercent = useRealDay ? dayChangePercent
            : useRealAllTime ? totalPnlPercent
            : (PortfolioPeriodChange.percent(ds.points) ?? dayChangePercent)
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
                Text(StorageService.formatAmount(totalValue, symbol: currencySymbol, decimals: storageService.amountDecimals))
                    .font(DS.display).tracking(-0.5)
                    .foregroundStyle(DS.ink)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.9), value: totalValue)
                HStack(spacing: 10) {
                    ChangePill(value: periodValue,
                               text: String(format: "%+.\(decimals)f%% %@", periodPercent, periodLabel))
                    // The all-time figure alongside — hidden on the All range,
                    // where the pill already shows exactly this (no duplicate).
                    if !useRealAllTime {
                        Text(String(format: "%@ (%+.\(decimals)f%%) all-time",
                                    StorageService.formatAmount(totalPnl, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                                    totalPnlPercent))
                            .font(DS.caption.monospacedDigit())
                            .foregroundStyle(DS.pnlColor(totalPnl))
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
    private func xAxisLabel(_ date: Date) -> String {
        switch chartRange {
        case .day: return date.formatted(.dateTime.hour().minute())
        case .week: return date.formatted(.dateTime.weekday(.abbreviated))
        case .month: return date.formatted(.dateTime.day().month(.abbreviated))
        case .year, .all: return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
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
                    AxisGridLine().foregroundStyle(DS.hairline.opacity(0.5))
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
                    if let d = value.as(Date.self) {
                        AxisValueLabel { Text(xAxisLabel(d)).font(DS.micro).foregroundStyle(DS.inkTertiary) }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in valueCrosshair(proxy, points: points, tint: tint) }
            // Morph marks in place when async data lands (avoids a hard "pop" as
            // intraday/history loads after a range switch).
            .animation(.easeInOut(duration: 0.4), value: points)
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

    private var statRow: some View {
        HStack(spacing: 12) {
            StatTile(label: "Total P&L",
                     value: StorageService.formatAmount(totalPnl, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                     caption: String(format: "%+.\(decimals)f%% on cost", totalPnlPercent),
                     captionTint: DS.pnlColor(totalPnl), valueTint: DS.pnlColor(totalPnl),
                     help: "Total profit/loss vs your cost basis")
            StatTile(label: "Today",
                     value: StorageService.formatAmount(dayChangeValue, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                     caption: String(format: "%+.\(decimals)f%%", dayChangePercent),
                     captionTint: DS.pnlColor(dayChangeValue), valueTint: DS.pnlColor(dayChangeValue),
                     help: "Change since the previous close")
            StatTile(label: "Invested",
                     value: StorageService.formatAmount(totalCost, symbol: currencySymbol, decimals: storageService.amountDecimals),
                     caption: "\(holdings.count) holdings",
                     help: "Total amount invested (cost basis)")
            StatTile(label: "Concentration",
                     value: String(format: "%.1f%%", topWeight),
                     caption: topSymbol.map { topWeight > 40 ? "high · top \($0)" : "top · \($0)" } ?? "—",
                     captionTint: topWeight > 40 ? DS.gold : DS.inkTertiary,
                     help: "Weight of your largest position — a diversification risk gauge")
        }
    }

    private var topSymbol: String? { allocation.first?.symbol }
    private var topWeight: Double { (allocation.first?.fraction ?? 0) * 100 }

    // MARK: - Allocation (donut + legend + type strip)

    private struct AllocationSlice: Identifiable {
        let id: String
        let symbol: String
        let value: Double
        let fraction: Double
    }
    private var allocation: [AllocationSlice] {
        let total = holdings.reduce(0) { $0 + abs($1.value) }
        guard total >= 0.01 else { return [] }
        var bySymbol: [String: Double] = [:]
        for h in holdings { bySymbol[h.symbol, default: 0] += abs(h.value) }
        return bySymbol.map { AllocationSlice(id: $0.key, symbol: $0.key, value: $0.value, fraction: $0.value / total) }
            .sorted { $0.value > $1.value }
    }

    private var allocationCard: some View {
        Card(title: "Allocation") {
            if allocation.isEmpty {
                emptyLine
            } else {
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        ZStack {
                            Chart(allocation) { slice in
                                SectorMark(angle: .value("Value", slice.value),
                                           innerRadius: .ratio(0.64), angularInset: 2)
                                    .cornerRadius(3)
                                    .foregroundStyle(color(for: slice.symbol))
                                    .opacity(hoveredSlice == nil || hoveredSlice == slice.symbol ? 1 : 0.35)
                            }
                            .chartLegend(.hidden)
                            VStack(spacing: 1) {
                                Text("\(allocation.count)").font(DS.figureLG).foregroundStyle(DS.ink)
                                SectionLabel("Assets")
                            }
                        }
                        .frame(width: 136, height: 136)

                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(allocation.prefix(6)) { slice in
                                HStack(spacing: 9) {
                                    RoundedRectangle(cornerRadius: 2.5).fill(color(for: slice.symbol)).frame(width: 9, height: 9)
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

                    if !typeBreakdown.isEmpty {
                        Divider().overlay(DS.hairline)
                        typeStrip
                    }
                }
            }
        }
    }

    private var typeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private func color(for symbol: String) -> Color {
        let idx = allocation.firstIndex { $0.symbol == symbol } ?? 0
        return DS.palette[idx % DS.palette.count]
    }

    // MARK: - Movers

    private func moversCard(proxy: ScrollViewProxy) -> some View {
        Card(title: "Today's movers") {
            var seen = Set<String>()
            let movers = holdings.filter { seen.insert($0.symbol).inserted }
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
                    if holdings.count > 5 {
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

    private var typeBreakdown: [(label: String, fraction: Double)] {
        let total = holdings.reduce(0) { $0 + abs($1.value) }
        guard total >= 0.01 else { return [] }
        var byType: [String: Double] = [:]
        for h in holdings { byType[Self.typeLabel(h.type), default: 0] += abs(h.value) }
        return byType.map { ($0.key, $0.value / total) }.sorted { $0.1 > $1.1 }
    }
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

    private var positionsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionLabel("Positions")
                Spacer()
                addHoldingButton
            }
            if holdings.isEmpty {
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
                    ForEach(holdings) { h in
                        NavigationLink(value: h.id) {
                            PositionRow(h: h, currencySymbol: currencySymbol,
                                        weight: abs(totalValue) >= 0.01 ? abs(h.value) / abs(totalValue) * 100 : 0,
                                        topWeight: topWeight,
                                        decimals: decimals,
                                        valueDecimals: storageService.valueDecimals)
                        }
                        .buttonStyle(.plain)
                        .help("View \(h.symbol) details · right-click to edit or delete")
                        .contextMenu {
                            Button { editHoldingAction.perform(h.portfolioId, h.holding) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) {
                                storageService.removeHolding(from: h.portfolioId, holdingId: h.holding.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        if h.id != holdings.last?.id {
                            Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let h = holdings.first(where: { $0.id == id }) {
                        HoldingDetailView(holding: h.holding, quote: h.quote, value: h.value, cost: h.cost,
                                          weight: abs(totalValue) >= 0.01 ? abs(h.value) / abs(totalValue) * 100 : 0)
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
                    Text(h.name).font(DS.micro).foregroundStyle(DS.inkTertiary).lineLimit(1)
                }
            }
            .frame(width: 168, alignment: .leading)

            Text(StorageService.formatAmount(h.quote.displayPrice(extendedHours: false), symbol: currencySymbol, decimals: priceDec(h.quote.displayPrice(extendedHours: false))))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .font(DS.figure).foregroundStyle(DS.ink)
                .contentTransition(.numericText())
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
