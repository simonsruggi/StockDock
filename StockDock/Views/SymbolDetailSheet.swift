import SwiftUI

/// Full chart sheet for any watchlist symbol (double-click a row): the shared
/// price chart card plus the 52-week range and day facts — the same look as the
/// holding detail, without a position.
struct SymbolDetailSheet: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    let symbol: String
    var onAddToPortfolio: (UUID) -> Void = { _ in }
    let onDismiss: () -> Void

    private var quote: StockQuote? { stockService.quotes[symbol] }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.gap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(symbol).font(DS.titleXL).tracking(-0.3).foregroundStyle(DS.ink)
                    if let name = quote?.name, !name.isEmpty {
                        Text(name).font(DS.caption).foregroundStyle(DS.inkTertiary)
                    }
                }
                Spacer()
                if !storageService.portfolios.isEmpty {
                    DSMenu(width: 220, sections: [storageService.portfolios.map { p in
                        DSMenuAction(title: p.name, icon: "briefcase") { onAddToPortfolio(p.id) }
                    }]) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text("Add to Portfolio").font(.inter(12, weight: .semibold, relativeTo: .body))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(DS.brand))
                    }
                    .help("Add this stock as a position in a portfolio")
                }
                Button("Done", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.inter(12, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(DS.inkSecondary)
                    .keyboardShortcut(.defaultAction)
            }

            if let quote {
                PriceChartCard(symbol: symbol, quote: quote)
                HStack(alignment: .top, spacing: DS.gap) {
                    fiftyTwoWeekCard(quote).frame(maxWidth: .infinity)
                    factsCard(quote).frame(maxWidth: .infinity)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(24)
        .frame(width: 680)
        .background(DS.ground)
    }

    @ViewBuilder private func fiftyTwoWeekCard(_ quote: StockQuote) -> some View {
        if let pos = quote.fiftyTwoWeekPosition,
           let low = quote.fiftyTwoWeekLow, let high = quote.fiftyTwoWeekHigh {
            let priceSymbol = StorageService.currencySymbol(for: quote.currency)
            Card(title: "52-week range") {
                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.cardAlt).frame(height: 6)
                            Circle()
                                .fill(.white)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(DS.brand, lineWidth: 2))
                                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                .offset(x: CGFloat(pos) * (geo.size.width - 10))
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

    private func factsCard(_ quote: StockQuote) -> some View {
        Card(title: "Today") {
            VStack(spacing: 0) {
                if let low = quote.dayLow, let high = quote.dayHigh {
                    factRow("Day range", "\(StorageService.formatNumber(low, decimals: 2)) – \(StorageService.formatNumber(high, decimals: 2))")
                    divider
                }
                factRow("Currency", quote.currency)
                if quote.isExtendedHours, !quote.marketStateLabel.isEmpty {
                    divider
                    factRow("Session", quote.marketStateLabel)
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
}
