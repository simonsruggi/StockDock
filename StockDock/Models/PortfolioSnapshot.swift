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

/// Pure operations on a portfolio's snapshot log. Keeps at most one entry per
/// calendar day.
enum SnapshotLog {
    /// Inserts a snapshot keeping at most one per calendar day: an existing entry
    /// for the same day is replaced (so the latest intraday value wins), otherwise
    /// the snapshot is appended. The result is always sorted chronologically.
    static func upsert(_ snapshot: PortfolioSnapshot,
                       into log: [PortfolioSnapshot],
                       calendar: Calendar = .current) -> [PortfolioSnapshot] {
        var out = log.filter { !calendar.isDate($0.date, inSameDayAs: snapshot.date) }
        out.append(snapshot)
        out.sort { $0.date < $1.date }
        return out
    }

    /// True when the log has no entry for the given day yet.
    static func isNewDay(_ date: Date, in log: [PortfolioSnapshot], calendar: Calendar = .current) -> Bool {
        !log.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
