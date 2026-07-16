import SwiftUI
import Charts

/// The real price-history card: live price + range picker + one year of Yahoo
/// daily closes. Shared by the holding detail page and the watchlist symbol
/// sheet, so every chart in the app looks and behaves the same.
struct PriceChartCard: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    let symbol: String
    let quote: StockQuote

    enum ChartRange: String, CaseIterable {
        case day = "24H", week = "7D", month = "1M", year = "1Y", all = "All"
        /// Lookback window in days; nil = the whole fetched history.
        var days: Int? {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return nil
            }
        }
        /// 24H uses the 5-minute intraday feed; the rest use daily closes.
        var isIntraday: Bool { self == .day }
    }
    @State private var chartRange: ChartRange = .month
    @State private var hoverPoint: PricePoint?

    private var priceSymbol: String { StorageService.currencySymbol(for: quote.currency) }

    private func hoverLabel(_ date: Date) -> String {
        chartRange.isIntraday ? date.formatted(.dateTime.hour().minute())
                              : date.formatted(date: .abbreviated, time: .omitted)
    }

    /// X-axis tick label, formatted for the selected period.
    private func xAxisLabel(_ date: Date) -> String {
        switch chartRange {
        case .day: return date.formatted(.dateTime.hour().minute())
        case .week: return date.formatted(.dateTime.weekday(.abbreviated))
        case .month: return date.formatted(.dateTime.day().month(.abbreviated))
        case .year, .all: return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    /// Smooth hover crosshair drawn as an overlay (not chart marks), so moving the
    /// mouse doesn't re-render the whole chart. Vertical rule + dot + tooltip.
    @ViewBuilder private func chartCrosshair(_ proxy: ChartProxy, tint: Color) -> some View {
        GeometryReader { geo in
            if let plotAnchor = proxy.plotFrame {
                let plot = geo[plotAnchor]
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                let localX = min(max(loc.x - plot.minX, 0), plot.width)
                                if let d: Date = proxy.value(atX: localX) {
                                    hoverPoint = nearestByDate(history, to: d, date: \.date)
                                }
                            case .ended:
                                hoverPoint = nil
                            }
                        }
                    if let h = hoverPoint,
                       let px = proxy.position(forX: h.date),
                       let py = proxy.position(forY: h.close) {
                        let cx = plot.minX + px
                        // Decorations must not steal hover from the catcher above.
                        Group {
                            Path { p in p.move(to: CGPoint(x: cx, y: plot.minY)); p.addLine(to: CGPoint(x: cx, y: plot.maxY)) }
                                .stroke(DS.inkTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            Circle().fill(tint).frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .position(x: cx, y: plot.minY + py)
                            ChartTooltip(title: hoverLabel(h.date),
                                         value: "\(priceSymbol)\(StorageService.formatNumber(h.close, decimals: storageService.resolvedPriceDecimals(symbol: symbol, price: h.close)))",
                                         tint: tint)
                                .position(x: min(max(cx, plot.minX + 50), plot.maxX - 50), y: plot.minY + 12)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var history: [PricePoint] {
        if chartRange.isIntraday {
            return stockService.intradayHistory[symbol] ?? []
        }
        if chartRange == .all {
            return stockService.priceHistoryMax[symbol] ?? []
        }
        guard let all = stockService.priceHistory[symbol] else { return [] }
        guard let days = chartRange.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return all }
        return all.filter { $0.date >= cutoff }
    }

    private var isLoadingCurrent: Bool {
        switch chartRange {
        case .day: return stockService.intradayHistory[symbol] == nil
        case .all: return stockService.priceHistoryMax[symbol] == nil
        default: return stockService.priceHistory[symbol] == nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Last price")
                    Text(StorageService.formatAmount(quote.displayPrice(extendedHours: storageService.showExtendedHours), symbol: priceSymbol))
                        .font(.inter(32, weight: .bold, relativeTo: .largeTitle).monospacedDigit())
                        .tracking(-0.4)
                        .foregroundStyle(DS.ink)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: quote.displayPrice(extendedHours: storageService.showExtendedHours))
                    HStack(spacing: 8) {
                        ChangePill(value: quote.change,
                                   text: String(format: "%+.\(storageService.percentDecimals)f%% today", quote.changePercent))
                        Text(StorageService.formatAmount(quote.change, symbol: priceSymbol, signed: true))
                            .font(DS.caption.monospacedDigit())
                            .foregroundStyle(DS.pnlColor(quote.change))
                    }
                }
                Spacer()
                // The picker appears with the data — no dead control while loading.
                if (stockService.priceHistory[symbol]?.count ?? 0) >= 2 { rangePicker }
            }
            .padding(DS.pad)

            chart
                .frame(height: 190)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .premiumCard()
        .task(id: symbol) { await stockService.ensurePriceHistory(for: symbol) }
        .task(id: "\(symbol)-\(chartRange.rawValue)") {
            if chartRange.isIntraday { await stockService.ensureIntraday(for: symbol) }
            if chartRange == .all { await stockService.ensurePriceHistoryMax(for: symbol) }
        }
    }

    private var rangePicker: some View {
        SegmentedRangePicker(options: ChartRange.allCases, label: \.rawValue, selection: $chartRange)
    }

    @ViewBuilder private var chart: some View {
        if history.count >= 2 {
            // Tint follows the period's direction.
            let periodUp = (history.last?.close ?? 0) >= (history.first?.close ?? 0)
            let tint = periodUp ? DS.up : DS.down
            Chart {
                ForEach(history) { point in
                    AreaMark(x: .value("Day", point.date), y: .value("Close", point.close))
                        .foregroundStyle(.linearGradient(colors: [tint.opacity(0.25), tint.opacity(0)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", point.date), y: .value("Close", point.close))
                        .foregroundStyle(tint).lineStyle(.init(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                if let last = history.last {
                    PointMark(x: .value("Day", last.date), y: .value("Close", last.close))
                        .symbolSize(50)
                        .foregroundStyle(tint)
                }
            }
            .chartYScale(domain: chartDomain)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(DS.hairline)
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(StorageService.formatNumber(d, decimals: d >= 100 ? 0 : 2))
                                .font(DS.micro).foregroundStyle(DS.inkTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(DS.hairline.opacity(0.5))
                    if let d = value.as(Date.self) {
                        AxisValueLabel { Text(xAxisLabel(d)).font(DS.micro).foregroundStyle(DS.inkTertiary) }
                    }
                }
            }
            .chartOverlay { proxy in chartCrosshair(proxy, tint: tint) }
            .id(chartRange)
            .transition(.opacity.animation(.easeInOut(duration: 0.28)))
            .padding(.horizontal, DS.pad).padding(.bottom, 12)
        } else {
            ZStack {
                DS.cardAlt
                DecorativeCurve()
                    .stroke(DS.hairline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .padding(.horizontal, 24)
                VStack(spacing: 5) {
                    if isLoadingCurrent {
                        ProgressView().scaleEffect(0.6)
                        Text("Loading price history…")
                            .font(.inter(11, weight: .medium, relativeTo: .caption)).foregroundStyle(DS.inkSecondary)
                    } else {
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 20)).foregroundStyle(DS.inkTertiary)
                        Text("No price history available")
                            .font(.inter(11, weight: .medium, relativeTo: .caption)).foregroundStyle(DS.inkSecondary)
                    }
                }
            }
        }
    }

    private var chartDomain: ClosedRange<Double> {
        let closes = history.map(\.close)
        guard let min = closes.min(), let max = closes.max(), max > min else { return 0...1 }
        let pad = (max - min) * 0.12
        return (min - pad)...(max + pad)
    }
}

/// A tiny 30-day price line for table rows — no axes, tinted by direction.
/// Lazily triggers the (cached) history fetch for its symbol.
///
/// Reads the shared service directly (not @EnvironmentObject): `Table` cells on
/// macOS are hosted outside the SwiftUI environment chain, so an environment
/// object would crash here.
struct Sparkline: View {
    @ObservedObject private var stockService = StockService.shared
    let symbol: String

    private var points: [PricePoint] {
        guard let all = stockService.priceHistory[symbol],
              let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        else { return [] }
        return all.filter { $0.date >= cutoff }
    }

    var body: some View {
        Group {
            if points.count >= 2 {
                let up = (points.last?.close ?? 0) >= (points.first?.close ?? 0)
                let tint = up ? DS.up : DS.down
                Chart(points) { point in
                    LineMark(x: .value("Day", point.date), y: .value("Close", point.close))
                        .foregroundStyle(tint).lineStyle(.init(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: sparkDomain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
            } else {
                Capsule().fill(DS.cardAlt).frame(height: 2)
            }
        }
        .frame(width: 64, height: 22)
        // History is filled by the watchlist's batched spark request, so no
        // per-row fetch here (that would be one request per symbol).
    }

    private var sparkDomain: ClosedRange<Double> {
        let closes = points.map(\.close)
        guard let min = closes.min(), let max = closes.max(), max > min else { return 0...1 }
        return min...max
    }
}
