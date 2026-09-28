import SwiftUI

struct TotalFooter: View {
    let value: Double
    let cost: Double
    let currency: String
    var decimals: Int = 2

    var body: some View {
        let symbol = StorageService.currencySymbol(for: currency)
        let pnl = value - cost
        // Same convention as the popover: amount and percentage, always together.
        let pct: Double? = abs(cost) >= 0.01 ? (pnl / abs(cost)) * 100 : nil
        VStack(alignment: .leading, spacing: 3) {
            Divider().overlay(DS.hairline)
            SectionLabel("Total portfolio").padding(.top, 10)
            Text(StorageService.formatAmount(value, symbol: symbol, decimals: decimals))
                .font(.inter(17, weight: .bold, relativeTo: .title3).monospacedDigit())
                .foregroundStyle(DS.ink)
                .contentTransition(.numericText())
            HStack(spacing: 5) {
                Image(systemName: pnl >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text(StorageService.formatAmount(pnl, symbol: symbol, decimals: decimals, signed: true)
                     + (pct.map { String(format: " (%+.1f%%)", $0) } ?? ""))
                    .font(.inter(11, weight: .medium, relativeTo: .caption).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(DS.pnlColor(pnl))
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}
