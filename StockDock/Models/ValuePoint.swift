import Foundation

/// A reconstructed point on the estimated portfolio value curve.
struct ValuePoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}
