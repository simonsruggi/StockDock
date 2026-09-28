import Foundation

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
