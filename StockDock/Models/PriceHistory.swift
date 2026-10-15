import Foundation

/// Pure transforms over Yahoo v8 chart arrays.
enum PriceHistory {
    /// Pairs the v8 chart `timestamp` array with the `close` array into
    /// chronological price points, skipping nil holes (holidays/halts) and
    /// defensively truncating to the shortest array.
    static func points(timestamps: [Int], closes: [Double?]) -> [PricePoint] {
        zip(timestamps, closes)
            .compactMap { ts, close in
                close.map { PricePoint(date: Date(timeIntervalSince1970: TimeInterval(ts)), close: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    /// The bars belonging to the most recent trading session in `points`.
    ///
    /// Yahoo's `range=1d` returns nothing until today's session actually prints
    /// — before the open, at weekends and on holidays — which left the 24H chart
    /// empty for a good part of the week. The app asks for two days instead and
    /// keeps the last session that has data, so the range always draws the most
    /// recent one (the same thing Stocks.app shows outside market hours).
    ///
    /// Sessions are split on the time gap rather than the calendar day: a US
    /// session straddles midnight for anyone east of London, and a day boundary
    /// would cut it in half.
    static func lastSession(_ points: [PricePoint], gap: TimeInterval = 3600) -> [PricePoint] {
        guard points.count > 1 else { return points }
        for i in stride(from: points.count - 1, to: 0, by: -1)
        where points[i].date.timeIntervalSince(points[i - 1].date) > gap {
            return Array(points[i...])
        }
        return points
    }

    /// The bars for a 24H range that includes pre/post-market: the most recent
    /// trading block (pre + regular + post, split on the overnight gap), plus the
    /// block before it while the latest one is still too short to hold a regular
    /// session — i.e. during pre-market, when it would otherwise show only a few
    /// minutes. Symbols with no gap at all (crypto) are cut to the last `maxSpan`.
    static func recentSessions(_ points: [PricePoint], gap: TimeInterval = 3600,
                               minSpan: TimeInterval = 6 * 3600, maxSpan: TimeInterval = 24 * 3600) -> [PricePoint] {
        guard let lastDate = points.last?.date else { return points }
        let last = lastSession(points, gap: gap)
        var result = last
        if let first = last.first, lastDate.timeIntervalSince(first.date) < minSpan, last.count < points.count {
            let previous = lastSession(Array(points[..<(points.count - last.count)]), gap: gap)
            result = previous + last
        }
        if let first = result.first, lastDate.timeIntervalSince(first.date) > maxSpan, last.count == points.count {
            result = result.filter { lastDate.timeIntervalSince($0.date) <= maxSpan }
        }
        return result
    }
}
