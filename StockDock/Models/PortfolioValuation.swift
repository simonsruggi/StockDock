import Foundation

/// Pure aggregation of a portfolio's value and cost in the preferred currency.
/// FX rates and the display price are resolved by the caller (which has the live
/// quotes), keeping the math here testable without any services.
enum PortfolioValuation {
    /// One holding's resolved inputs. Holdings without a live quote are simply
    /// omitted by the caller rather than represented here.
    struct Input {
        var holding: Holding
        /// Display price in the stock's own currency (already respects the
        /// extended-hours preference).
        var price: Double
        /// Stock currency → preferred currency, at the current rate.
        var rate: Double
        /// Stock currency → preferred currency, at the holding's purchase date.
        var costRate: Double
    }

    /// Aggregate market value and cost basis in the preferred currency, reusing
    /// the signed, leverage-aware math on `Holding`.
    static func totals(_ inputs: [Input]) -> (value: Double, cost: Double) {
        var value = 0.0
        var cost = 0.0
        for i in inputs {
            value += i.holding.marketValue(currentPrice: i.price) * i.rate
            cost += i.holding.costBasisLocal * i.costRate
        }
        return (value, cost)
    }
}
