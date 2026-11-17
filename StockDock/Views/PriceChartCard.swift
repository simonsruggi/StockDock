import SwiftUI

/// The real price-history card: live price + range picker + Yahoo history.
/// Shared by the holding detail page and the watchlist symbol sheet, so every
/// chart in the app looks and behaves the same.
struct PriceChartCard: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @ObservedObject var allHoursService = HyperliquidService.shared
    let symbol: String
    let quote: StockQuote
    /// Average purchase price of the holding, drawn as a dashed line on the chart.
    var costBasis: Double? = nil

    /// #14: seeded from the last range the user picked (see `restoreRange`), so
    /// the chart opens where they left it instead of always on 1M.
    @State var chartRange: ChartRange = .month

    /// Applies the remembered range, if there is a valid one stored.
    private func restoreRange() {
        if let saved = ChartRange(rawValue: storageService.lastSymbolChartRange) {
            chartRange = saved
        }
    }

    var priceSymbol: String { StorageService.currencySymbol(for: quote.currency) }

    var body: some View {
        let points = history
        let livePrice = HyperliquidService.shared.livePrice(for: quote, extendedHours: storageService.showExtendedHours)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Last price")
                        Text(StorageService.formatAmount(livePrice, symbol: priceSymbol))
                            .font(.inter(32, weight: .bold, relativeTo: .largeTitle).monospacedDigit())
                            .tracking(-0.4)
                            .foregroundStyle(DS.ink)
                            .contentTransition(.numericText())
                            // Price-driven: must settle between 1s tick flushes (see DS.tick).
                            .animation(DS.tick, value: livePrice)
                    }
                    Spacer(minLength: 12)
                    // The picker appears with the data — no dead control while loading.
                    if (stockService.priceHistory[symbol]?.count ?? 0) >= 2 { rangePicker.fixedSize() }
                }
                // On its own row: with nine ranges the picker takes most of the
                // header's width, and the pills would be squeezed beside it.
                HStack(spacing: 8) {
                    ChangePill(value: quote.change,
                               text: String(format: "%+.\(storageService.percentDecimals)f%% today", quote.changePercent))
                    Text(StorageService.formatAmount(quote.change, symbol: priceSymbol, signed: true))
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(DS.pnlColor(quote.change))
                    if let period = periodChange(points, livePrice: livePrice) {
                        ChangePill(value: period,
                                   text: String(format: "%+.\(storageService.percentDecimals)f%% · ", period) + chartRange.rawValue)
                            .help("Change over the selected range, to the live price")
                    }
                }
            }
            .padding(DS.pad)

            chart(points)
                .frame(height: 190)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .premiumCard()
        .task(id: symbol) { await stockService.ensurePriceHistory(for: symbol) }
        .task(id: "\(symbol)-\(chartRange.rawValue)") {
            switch chartRange {
            case .day: await stockService.ensureIntraday(for: symbol)
            case .fiveYears: await stockService.ensurePriceHistory5y(for: symbol)
            case .all: await stockService.ensurePriceHistoryMax(for: symbol)
            default: break
            }
        }
    }

    private var rangePicker: some View {
        SegmentedRangePicker(options: ChartRange.allCases, label: \.rawValue, selection: $chartRange)
            .onAppear(perform: restoreRange)
            .onChange(of: chartRange) { _, new in
                storageService.lastSymbolChartRange = new.rawValue
            }
    }

    @ViewBuilder private func chart(_ points: [PricePoint]) -> some View {
        if points.count >= 2 {
            PriceChartPlot(points: points, range: chartRange, up: DS.up, down: DS.down,
                           priceSymbol: priceSymbol,
                           priceDecimals: storageService.resolvedPriceDecimals(symbol: symbol, price: points.last?.close ?? 0),
                           percentDecimals: storageService.percentDecimals,
                           costBasis: costBasis)
                .equatable()
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
}
