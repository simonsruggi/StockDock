import SwiftUI

struct HoldingRow: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.editHoldingAction) var editHoldingAction
    let holding: Holding
    let portfolioId: UUID

    var quote: StockQuote? {
        stockService.quotes[holding.symbol]
    }

    /// #24: the price-display conversion for this row, decided once so the
    /// figure and the symbol always come from the same source.
    private var priced: (rate: Double, currency: String) {
        guard let quote else { return (1.0, "") }
        return stockService.priceDisplay(for: quote.currency)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1: Ticker + Qty@Avg
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(holding.symbol)
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.bold)
                    if holding.isShort {
                        Text("SHORT")
                            .font(.inter(8, weight: .bold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(DS.down))
                    }
                    if holding.effectiveLeverage != 1 {
                        Text("\(StorageService.formatNumber(holding.effectiveLeverage, decimals: holding.effectiveLeverage == holding.effectiveLeverage.rounded() ? 0 : 1))\u{00D7}")
                            .font(.inter(8, weight: .bold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(DS.brand))
                    }
                }
                // #24: the avg price sits right under the Last column, so it has
                // to be in the same currency — it was printed raw while Last was
                // converted, which is what made people convert it by hand.
                Text("\(StorageService.formatQuantity(holding.quantity))\u{00D7}\(StorageService.formatNumber(holding.avgPrice * priced.rate, decimals: 2))")
                    .font(.inter(10, relativeTo: .caption).monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 88, alignment: .leading)

            if let quote {
                let rate = stockService.rate(from: quote.currency)
                let pRate = priced.rate
                let priceSymbol = StorageService.currencySymbol(for: priced.currency)
                let prefSymbol = StorageService.currencySymbol(for: storageService.preferredCurrency)

                // Col 2: Price + badge
                HStack(spacing: 3) {
                    Text("\(priceSymbol)\(StorageService.formatNumber(quote.displayPrice(extendedHours: storageService.showExtendedHours) * pRate, decimals: storageService.resolvedPriceDecimals(symbol: quote.symbol, price: quote.displayPrice(extendedHours: storageService.showExtendedHours) * pRate)))")
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.medium)
                    if storageService.showExtendedHours, quote.isExtendedHours, !quote.marketStateLabel.isEmpty {
                        Text(quote.marketStateLabel)
                            .font(.inter(9, weight: .semibold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(quote.marketState.hasPrefix("PRE") ? DS.gold : DS.palette[3])
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                // Col 3: Controvalore + P&L in preferred currency
                let displayPrice = quote.displayPrice(extendedHours: storageService.showExtendedHours)
                let marketVal = holding.marketValue(currentPrice: displayPrice) * rate
                let costRate = stockService.rate(from: quote.currency, for: holding.purchaseDate)
                let costBasis = holding.costBasisLocal * costRate
                let pnl = marketVal - costBasis
                let pnlPct = abs(costBasis) >= 0.01 ? (pnl / abs(costBasis)) * 100 : 0

                VStack(alignment: .trailing, spacing: 1) {
                    Text(StorageService.formatAmount(marketVal, symbol: prefSymbol, decimals: storageService.amountDecimals))
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.medium)
                    Text("\(StorageService.formatAmount(pnl, symbol: prefSymbol, decimals: storageService.amountDecimals, signed: true)) (\(String(format: "%.\(storageService.percentDecimals)f%%", pnlPct)))")
                        .font(.inter(10, relativeTo: .caption).monospacedDigit())
                        .foregroundColor(pnl >= 0 ? DS.up : DS.down)
                }
                .frame(width: 120, alignment: .trailing)
            } else {
                Spacer()
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                editHoldingAction.perform(portfolioId, holding)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                storageService.removeHolding(from: portfolioId, holdingId: holding.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
