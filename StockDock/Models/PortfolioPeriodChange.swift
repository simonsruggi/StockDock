import Foundation

/// Change of a drawn value curve over its own span — the delta between its first
/// and last points. Drives the hero pill so it reflects the *selected* period
/// (24H/7D/1M/…) instead of always showing the day-over-day change.
enum PortfolioPeriodChange {
    /// Absolute change (last − first) over the series, or nil if under 2 points.
    static func value(_ points: [ValuePoint]) -> Double? {
        guard let first = points.first?.value, let last = points.last?.value,
              points.count >= 2 else { return nil }
        return last - first
    }

    /// Percentage change vs the first point, or nil if the span is degenerate
    /// (fewer than 2 points, or a starting value too close to zero to divide by).
    static func percent(_ points: [ValuePoint]) -> Double? {
        guard let first = points.first?.value, let last = points.last?.value,
              points.count >= 2, abs(first) >= 0.01 else { return nil }
        return (last - first) / abs(first) * 100
    }
}
