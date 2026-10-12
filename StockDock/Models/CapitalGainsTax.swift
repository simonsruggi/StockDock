import Foundation

/// P&L net of the user's capital-gains tax rate. Only gains are taxed: a loss
/// is shown unchanged (it's a tax credit, not a tax bill). Works on both
/// amounts and percentages, since the tax scales a gain linearly.
///
/// Totals are taxed on the netted sum (gains minus losses), the way a capital
/// gains regime offsets them, so the sum of per-position net figures can differ
/// from the net total when the portfolio mixes winners and losers.
enum CapitalGainsTax {
    static func net(_ pnl: Double, ratePercent: Double) -> Double {
        guard pnl > 0, ratePercent > 0 else { return pnl }
        return pnl * (1 - min(ratePercent, 100) / 100)
    }
}
