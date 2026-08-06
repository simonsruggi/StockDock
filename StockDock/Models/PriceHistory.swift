import Foundation

/// A daily closing price for the detail chart.
struct PricePoint: Identifiable, Equatable {
    let date: Date
    let close: Double
    var id: Date { date }
}

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
}
