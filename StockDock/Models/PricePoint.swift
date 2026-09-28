import Foundation

/// A daily closing price for the detail chart.
struct PricePoint: Identifiable, Equatable {
    let date: Date
    let close: Double
    var id: Date { date }
}
