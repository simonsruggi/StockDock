import Foundation

struct Portfolio: Identifiable, Codable {
    var id: UUID
    var name: String
    var holdings: [Holding]
    /// Issue #14: keep this portfolio out of the combined total — a paper/fantasy
    /// portfolio you want to track without it moving your real net worth. It's
    /// still a full portfolio: own chart, own snapshots, own notifications.
    /// Optional so portfolios saved before 1.9.12 decode cleanly as counted.
    var excludedFromTotal: Bool?

    init(id: UUID = UUID(), name: String, holdings: [Holding] = [], excludedFromTotal: Bool? = nil) {
        self.id = id
        self.name = name
        self.holdings = holdings
        self.excludedFromTotal = excludedFromTotal
    }

    /// True when this portfolio must not contribute to any combined figure.
    var isExcludedFromTotal: Bool { excludedFromTotal == true }
}
