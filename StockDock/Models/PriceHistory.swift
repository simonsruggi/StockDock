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
}
