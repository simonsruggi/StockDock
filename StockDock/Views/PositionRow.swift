import SwiftUI

struct PositionRow: View {
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

    // #24: Last and Change are per-share prices, so they carry the stock's own
    // conversion — never `currencySymbol`, which belongs to Value and P&L.
    private var priceSymbol: String { StorageService.currencySymbol(for: h.priceCurrency) }
    private var lastPrice: Double { h.quote.displayPrice(extendedHours: false) * h.priceRate }
    private var lastChange: Double { h.quote.change * h.priceRate }

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

            Text(StorageService.formatAmount(lastPrice, symbol: priceSymbol, decimals: priceDec(lastPrice)))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .font(DS.figure).foregroundStyle(DS.ink)
                .contentTransition(.numericText())
            VStack(alignment: .trailing, spacing: 1) {
                ChangePill(value: lastChange,
                           text: StorageService.formatAmount(lastChange, symbol: "", decimals: priceDec(lastChange), signed: true, truncateZeros: true))
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
