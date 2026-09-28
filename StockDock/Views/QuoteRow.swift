import SwiftUI

struct QuoteRow: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    let quote: StockQuote

    /// #24: rate and currency are read together, so a row can never show a
    /// native figure under another currency's symbol while the FX pair loads.
    private var priced: (rate: Double, currency: String) {
        stockService.priceDisplay(for: quote.currency)
    }

    private var displayCurrency: String { priced.currency }

    private var priceRate: Double { priced.rate }

    private var currSymbol: String {
        StorageService.currencySymbol(for: displayCurrency)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1: Symbol + name
            VStack(alignment: .leading, spacing: 1) {
                // #12: the custom name replaces the ticker on the primary line;
                // the real ticker moves to the secondary line so it's never lost.
                Text(storageService.displayLabel(for: quote.symbol, fallback: quote.symbol))
                    .font(.inter(13, relativeTo: .body).monospacedDigit())
                    .fontWeight(.bold)
                    .lineLimit(1)
                if !storageService.alias(for: quote.symbol).isEmpty {
                    Text(quote.symbol)
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if storageService.showCompanyName {
                    Text(quote.name)
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 80, alignment: .leading)

            // Col 2: Price + day range
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Text("\(currSymbol)\(StorageService.formatNumber(quote.displayPrice(extendedHours: storageService.showExtendedHours) * priceRate, decimals: storageService.resolvedPriceDecimals(symbol: quote.symbol, price: quote.displayPrice(extendedHours: storageService.showExtendedHours) * priceRate)))")
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
                if storageService.showDayRange, let high = quote.dayHigh, let low = quote.dayLow {
                    let rangeDecimals = storageService.resolvedPriceDecimals(symbol: quote.symbol, price: low * priceRate)
                    Text("\(StorageService.formatNumber(low * priceRate, decimals: rangeDecimals)) – \(StorageService.formatNumber(high * priceRate, decimals: rangeDecimals))")
                        .font(.inter(10, relativeTo: .caption).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                if storageService.show52WeekBar,
                   let pos = quote.fiftyTwoWeekPosition,
                   let low = quote.fiftyTwoWeekLow, let high = quote.fiftyTwoWeekHigh {
                    HStack(spacing: 4) {
                        Text(StorageService.formatNumber(low * priceRate, decimals: 0))
                            .font(.inter(8, relativeTo: .caption2).monospacedDigit())
                            .foregroundColor(.secondary)
                        RangeBar(position: pos)
                            .frame(width: 56)
                        Text(StorageService.formatNumber(high * priceRate, decimals: 0))
                            .font(.inter(8, relativeTo: .caption2).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .help("52-week range")
                }
            }
            .frame(maxWidth: .infinity)

            // Col 3: Change
            VStack(alignment: .trailing, spacing: 1) {
                if storageService.showAbsoluteChange {
                    Text(StorageService.formatAmount(quote.change * priceRate, symbol: currSymbol, signed: true))
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.medium)
                        .foregroundColor(quote.isPositive ? DS.up : DS.down)
                }
                Text(String(format: "%.\(storageService.percentDecimals)f%%", quote.changePercent))
                    .font(.inter(10, relativeTo: .caption).monospacedDigit())
                    .foregroundColor(quote.isPositive ? DS.up : DS.down)

                if storageService.showExtendedHours,
                   let extChg = quote.extendedChange,
                   let extPct = quote.extendedChangePercent {
                    Text(String(format: "%+.2f (%.\(storageService.percentDecimals)f%%)", extChg * priceRate, extPct))
                        .font(.inter(10, relativeTo: .caption).monospacedDigit())
                        .foregroundColor(extChg >= 0 ? DS.up.opacity(0.8) : DS.down.opacity(0.8))
                }
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
