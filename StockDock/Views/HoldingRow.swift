import SwiftUI

struct HoldingRow: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @ObservedObject var allHoursService = HyperliquidService.shared
    @Environment(\.editHoldingAction) var editHoldingAction
    let holding: Holding
    let portfolioId: UUID
    /// Every lot of the position when this row stands for several; empty for a single lot.
    var lots: [Holding] = []
    /// A lot shown under its expanded position: lighter, with its purchase date.
    var isLot = false
    /// Merged position: whether its lots are showing (drives the chevron).
    var expanded = false

    private var allLots: [Holding] { lots.isEmpty ? [holding] : lots }
    /// The position as displayed: the lots merged (shares summed, price averaged).
    private var shown: Holding { HoldingValues.merged(allLots) }

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
                    Text(isLot ? (holding.purchaseDate?.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)) ?? "—") : holding.symbol)
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.bold)
                    if lots.count > 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.inkTertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .animation(.easeOut(duration: 0.15), value: expanded)
                    }
                    if shown.isShort && !isLot {
                        Text("SHORT")
                            .font(.inter(8, weight: .bold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(DS.down))
                    }
                    if shown.effectiveLeverage != 1 && !isLot {
                        Text("\(StorageService.formatNumber(shown.effectiveLeverage, decimals: shown.effectiveLeverage == shown.effectiveLeverage.rounded() ? 0 : 1))\u{00D7}")
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
                Text("\(StorageService.formatQuantity(shown.quantity))\u{00D7}\(StorageService.formatNumber(shown.avgPrice * priced.rate, decimals: 2))")
                    .font(.inter(10, relativeTo: .caption).monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 88, alignment: .leading)

            if let quote {
                let pRate = priced.rate
                let priceSymbol = StorageService.currencySymbol(for: priced.currency)
                let prefSymbol = StorageService.currencySymbol(for: storageService.preferredCurrency)

                // Col 2: Price + badge
                let displayPrice = allHoursService.livePrice(for: quote, extendedHours: storageService.showExtendedHours)
                HStack(spacing: 3) {
                    Text("\(priceSymbol)\(StorageService.formatNumber(displayPrice * pRate, decimals: storageService.resolvedPriceDecimals(symbol: quote.symbol, price: displayPrice * pRate)))")
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.medium)
                    if allHoursService.quote(for: quote) != nil {
                        AllHoursBadge()
                    } else if storageService.showExtendedHours, quote.isExtendedHours, !quote.marketStateLabel.isEmpty {
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
                let values = HoldingValues(allLots, quote: quote, price: displayPrice,
                                           stockService: stockService, storageService: storageService)
                let marketVal = values.value
                let pnl = values.pnl
                let pnlPct = values.pnlPercent

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
        .opacity(isLot ? 0.85 : 1)
        .contextMenu {
            if lots.count <= 1 { lotActions }
        }
    }

    /// Edit and delete act on one lot, so a merged position offers them on its lots.
    @ViewBuilder private var lotActions: some View {
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
