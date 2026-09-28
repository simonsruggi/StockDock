import Foundation

/// A point-in-time valuation of a portfolio, captured once per calendar day so
/// the Portfolio window can chart value and P&L over time.
///
/// Snapshots accumulate *forward* from the day the feature ships. There is no
/// historical backfill: StockDock stores current positions, not a log of past
/// buys/sells, so a reconstructed past value ("as if today's holdings were held
/// all along") would be fiction. The per-symbol price chart in the detail view
/// uses Yahoo's real history instead.
struct PortfolioSnapshot: Identifiable, Codable, Equatable {
    var id: UUID
    /// The day this snapshot belongs to (normalized to the start of the local day
    /// when recorded), used for one-per-day de-duplication.
    var date: Date
    /// Total market value in the user's preferred currency at capture time.
    var totalValue: Double
    /// Total cost basis in the preferred currency at capture time.
    var totalCost: Double

    init(id: UUID = UUID(), date: Date, totalValue: Double, totalCost: Double) {
        self.id = id
        self.date = date
        self.totalValue = totalValue
        self.totalCost = totalCost
    }

    var totalPnl: Double { totalValue - totalCost }

    /// Return on cost. Uses the magnitude of the cost basis so mixed long/short
    /// baskets (where the signed cost can be near zero) still report a sensible %.
    var pnlPercent: Double {
        abs(totalCost) >= 0.01 ? (totalPnl / abs(totalCost)) * 100 : 0
    }
}
