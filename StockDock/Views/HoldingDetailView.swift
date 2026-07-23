import SwiftUI
import Charts

/// Per-holding detail reached from the positions table. Same page scaffold as
/// every tab (symbol + company in the fixed header), then: hero with the live
/// price and the real Yahoo price history chart, stat strip, 52-week range with
/// the purchase-price tick, and a position facts card.
struct HoldingDetailView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.editHoldingAction) private var editHoldingAction
    let portfolioId: UUID
    let holding: Holding
    let quote: StockQuote
    let value: Double
    let cost: Double
    let weight: Double

    @State private var showAlert = false

    private var currencySymbol: String {
        StorageService.currencySymbol(for: storageService.preferredCurrency)
    }
    private var priceSymbol: String {
        StorageService.currencySymbol(for: quote.currency)
    }
    private var pnl: Double { value - cost }
    private var pnlPercent: Double { abs(cost) >= 0.01 ? (pnl / abs(cost)) * 100 : 0 }

    private var relatedNews: [NewsArticle] {
        stockService.news.filter {
            $0.sourceSymbol == holding.symbol || $0.relatedTickers.contains(holding.symbol)
        }
    }

    var body: some View {
        PageScaffold(holding.symbol, caption: quote.name) {
            HStack(spacing: 10) {
                if holding.isShort { Tag(text: "SHORT", color: DS.down) }
                if holding.effectiveLeverage != 1 {
                    Tag(text: "\(StorageService.formatNumber(holding.effectiveLeverage, decimals: holding.effectiveLeverage == holding.effectiveLeverage.rounded() ? 0 : 1))×",
                        color: DS.brand)
                }
                Button { editHoldingAction.perform(portfolioId, holding) } label: {
                    Image(systemName: "pencil").font(.system(size: 12, weight: .medium)).foregroundStyle(DS.inkSecondary)
                }
                .buttonStyle(.plain)
                .help("Edit this holding")
                Button { showAlert = true } label: {
                    Image(systemName: "bell").font(.system(size: 12, weight: .medium)).foregroundStyle(DS.inkSecondary)
                }
                .buttonStyle(.plain)
                .help("Set a price alert")
                RefreshButton(isLoading: stockService.isLoading) {
                    Task { await stockService.refreshAll(storageService: storageService) }
                }
            }
        } content: {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.gap) {
                    PriceChartCard(symbol: holding.symbol, quote: quote)
                    statStrip
                    HStack(alignment: .top, spacing: DS.gap) {
                        fiftyTwoWeekCard.frame(maxWidth: .infinity)
                        factsCard.frame(maxWidth: .infinity)
                    }
                    if !relatedNews.isEmpty { newsCard }
                }
                .pageColumn()
                .padding(.top, 4)
            }
        }
        .navigationTitle(holding.symbol)
        .sheet(isPresented: $showAlert) {
            PriceAlertSheet(symbol: holding.symbol) { showAlert = false }
                .environmentObject(stockService).environmentObject(storageService)
        }
    }

    // MARK: - Related news

    private var newsCard: some View {
        Card(title: "Related news") {
            VStack(spacing: 0) {
                ForEach(relatedNews.prefix(5)) { article in
                    Button {
                        if let url = article.url { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(article.title).font(DS.body).foregroundStyle(DS.ink)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            if !article.publisher.isEmpty {
                                Text(article.publisher).font(DS.micro).foregroundStyle(DS.inkTertiary).lineLimit(1)
                            }
                            Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(DS.inkTertiary)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if article.id != relatedNews.prefix(5).last?.id {
                        Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    // MARK: - Stats

    private var statStrip: some View {
        HStack(spacing: 12) {
            StatTile(label: "Position", value: "\(formatQty(holding.quantity)) sh", help: "Shares you hold")
            StatTile(label: "Avg price", value: StorageService.formatAmount(holding.avgPrice, symbol: priceSymbol), help: "Your average purchase price")
            StatTile(label: "Value", value: StorageService.formatAmount(value, symbol: currencySymbol), help: "Current market value of this position")
            StatTile(label: "P&L",
                     value: StorageService.formatAmount(pnl, symbol: currencySymbol, signed: true),
                     caption: String(format: "%+.\(storageService.percentDecimals)f%%", pnlPercent),
                     captionTint: DS.pnlColor(pnl), valueTint: DS.pnlColor(pnl))
            StatTile(label: "Weight", value: String(format: "%.1f%%", weight), help: "Share of the portfolio")
        }
    }

    // MARK: - 52-week range

    @ViewBuilder private var fiftyTwoWeekCard: some View {
        if let pos = quote.fiftyTwoWeekPosition,
           let low = quote.fiftyTwoWeekLow, let high = quote.fiftyTwoWeekHigh {
            Card(title: "52-week range") {
                VStack(spacing: 10) {
                    GeometryReader { geo in
                        let x = CGFloat(pos) * (geo.size.width - 10)
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.cardAlt).frame(height: 6)
                            // Tick where the average purchase price sits ("you bought here").
                            if high > low {
                                let buyPos = min(max((holding.avgPrice - low) / (high - low), 0), 1)
                                Rectangle().fill(DS.inkTertiary)
                                    .frame(width: 1.5, height: 12)
                                    .offset(x: CGFloat(buyPos) * (geo.size.width - 10) + 4)
                                    .help("Your average purchase price")
                            }
                            Circle()
                                .fill(.white)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(DS.brand, lineWidth: 2))
                                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                .offset(x: x)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 16)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel("Low")
                            Text(StorageService.formatAmount(low, symbol: priceSymbol))
                                .font(DS.figure).foregroundStyle(DS.ink)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            SectionLabel("High")
                            Text(StorageService.formatAmount(high, symbol: priceSymbol))
                                .font(DS.figure).foregroundStyle(DS.ink)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Facts

    private var factsCard: some View {
        Card(title: "Position facts") {
            VStack(spacing: 0) {
                factRow("Purchase date", holding.purchaseDate.map { Self.dateFormatter.string(from: $0) } ?? "—")
                divider
                factRow("Cost basis", StorageService.formatAmount(cost, symbol: currencySymbol))
                divider
                factRow("Quote currency", quote.currency)
                if let lowD = quote.dayLow, let highD = quote.dayHigh {
                    divider
                    factRow("Day range", "\(StorageService.formatNumber(lowD, decimals: 2)) – \(StorageService.formatNumber(highD, decimals: 2))")
                }
            }
        }
    }

    private var divider: some View {
        Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label)).font(DS.caption).foregroundStyle(DS.inkSecondary)
            Spacer()
            Text(value).font(DS.figure).foregroundStyle(DS.ink)
        }
        .padding(.vertical, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func formatQty(_ qty: Double) -> String {
        qty == qty.rounded(.down) ? String(format: "%.0f", qty) : String(format: "%.2f", qty)
    }
}
