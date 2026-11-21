import SwiftUI

/// Portfolio chart hover card: the moment's total, then each position's price,
/// value and gain/loss against its cost.
struct PortfolioHoverTooltip: View {
    let title: String
    let total: String
    let tint: Color
    let rows: [HoverHolding]
    let currencySymbol: String
    let percentDecimals: Int
    /// Rows that fit in the chart's height; the rest collapse into "+N more".
    var maxRows = 6

    static let width: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(DS.micro).foregroundStyle(DS.inkTertiary)
                Spacer(minLength: 8)
                Text(total).font(.inter(12, weight: .semibold, relativeTo: .body).monospacedDigit()).foregroundStyle(tint)
            }
            if !rows.isEmpty {
                Rectangle().fill(DS.hairline).frame(height: 1)
                Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 2) {
                    ForEach(rows.prefix(maxRows)) { row in
                        GridRow {
                            Text(row.symbol)
                                .font(.inter(10.5, weight: .semibold, relativeTo: .caption).monospacedDigit())
                                .foregroundStyle(DS.ink).lineLimit(1)
                                .gridColumnAlignment(.leading)
                            Text(StorageService.formatAmount(row.price, symbol: row.priceSymbol))
                                .foregroundStyle(DS.inkSecondary)
                            Text(StorageService.formatAmount(row.value, symbol: currencySymbol, decimals: 0))
                                .foregroundStyle(DS.ink)
                            Text(String(format: "%+.\(percentDecimals)f%%", row.pnlPercent))
                                .foregroundStyle(DS.pnlColor(row.pnl))
                        }
                        .font(DS.micro.monospacedDigit())
                    }
                }
                if rows.count > maxRows {
                    Text("+\(rows.count - maxRows) more").font(DS.micro).foregroundStyle(DS.inkTertiary)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.card)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.hairline))
    }
}
