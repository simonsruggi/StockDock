import Foundation

/// A Hyperliquid 24/7 price, measured against the last regular close.
struct AllHoursQuote: Equatable {
    let coin: String
    let price: Double
    let change: Double
    let changePercent: Double
}
