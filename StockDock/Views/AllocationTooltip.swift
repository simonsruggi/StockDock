import SwiftUI

/// Hover card for one allocation slice: what was paid for the symbol, what it
/// is worth now and the P&L, summed over every lot and portfolio holding it.
struct AllocationTooltip: View {
    let symbol: String
    let holdings: [ValuedHolding]
    let weight: Double
    let tint: Color
    let currencySymbol: String
    let amountDecimals: Int
    let percentDecimals: Int
    let taxRate: Double

    static let width: CGFloat = 232

    private var invested: Double { holdings.reduce(0) { $0 + $1.cost } }
    private var value: Double { holdings.reduce(0) { $0 + $1.value } }
    private var quantity: Double { holdings.reduce(0) { $0 + $1.holding.quantity } }
    /// Shares × leverage: cost basis is leverage-scaled, so dividing it by the
    /// bare share count would overstate the price paid on leveraged lots.
    private var exposure: Double { holdings.reduce(0) { $0 + abs($1.holding.quantity) * $1.holding.effectiveLeverage } }
    private var pnl: Double { CapitalGainsTax.net(value - invested, ratePercent: taxRate) }
    private var pnlPercent: Double { abs(invested) >= 0.01 ? pnl / abs(invested) * 100 : 0 }
    private var name: String { holdings.first?.name ?? symbol }
    private var portfolioCount: Int { Set(holdings.map(\.portfolioId)).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 2.5).fill(tint).frame(width: 9, height: 9)
                Text(symbol).font(DS.figure).foregroundStyle(DS.ink)
                Spacer(minLength: 8)
                Text(String(format: "%.1f%%", weight)).font(DS.figure).foregroundStyle(DS.inkSecondary)
            }
            if name != symbol {
                Text(name).font(DS.caption).foregroundStyle(DS.inkTertiary).lineLimit(1)
            }
            Divider().overlay(DS.hairline)
            row("Invested", amount(invested))
            row("Value", amount(value))
            row("P&L", amount(pnl, signed: true) + String(format: "  %+.\(percentDecimals)f%%", pnlPercent),
                tint: DS.pnlColor(pnl))
            Divider().overlay(DS.hairline)
            row("Shares", StorageService.formatQuantity(quantity))
            if exposure > 0 {
                row("Avg cost", amount(abs(invested) / exposure))
            }
            if holdings.count > 1 {
                row(portfolioCount > 1 ? "Lots · portfolios" : "Lots",
                    portfolioCount > 1 ? "\(holdings.count) · \(portfolioCount)" : "\(holdings.count)")
            }
        }
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.card)
            .shadow(color: .black.opacity(0.14), radius: 10, y: 3))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline))
    }

    private func amount(_ v: Double, signed: Bool = false) -> String {
        StorageService.formatAmount(v, symbol: currencySymbol, decimals: amountDecimals, signed: signed)
    }

    private func row(_ label: String, _ value: String, tint: Color = DS.ink) -> some View {
        HStack {
            Text(label).font(DS.caption).foregroundStyle(DS.inkTertiary)
            Spacer(minLength: 10)
            Text(value).font(DS.caption.monospacedDigit()).foregroundStyle(tint)
        }
    }
}
