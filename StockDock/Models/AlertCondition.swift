import Foundation

/// The condition that makes a `PriceAlert` fire.
enum AlertCondition: String, Codable, CaseIterable {
    /// Fires when the price rises to/above the threshold (an absolute price).
    case priceAbove
    /// Fires when the price falls to/below the threshold (an absolute price).
    case priceBelow
    /// Fires when the daily change rises to/above the threshold (a positive percent).
    case dailyChangeUp
    /// Fires when the daily change falls to/below the negative threshold (a positive percent).
    case dailyChangeDown
    /// Fires when the price comes within `threshold`% of the 52-week high.
    case near52WeekHigh
    /// Fires when the price comes within `threshold`% of the 52-week low.
    case near52WeekLow

    /// Whether the threshold is an absolute price or a percentage.
    enum ThresholdKind { case price, percent }

    var thresholdKind: ThresholdKind {
        switch self {
        case .priceAbove, .priceBelow: return .price
        case .dailyChangeUp, .dailyChangeDown, .near52WeekHigh, .near52WeekLow: return .percent
        }
    }

    /// Short label for pickers.
    var label: String {
        switch self {
        case .priceAbove: return "Price rises above"
        case .priceBelow: return "Price drops below"
        case .dailyChangeUp: return "Daily change up by"
        case .dailyChangeDown: return "Daily change down by"
        case .near52WeekHigh: return "Near 52-week high"
        case .near52WeekLow: return "Near 52-week low"
        }
    }

    /// Compact label used under a symbol header, where "Price" is implied.
    var shortLabel: String {
        switch self {
        case .priceAbove: return "Above"
        case .priceBelow: return "Below"
        case .dailyChangeUp: return "Day up"
        case .dailyChangeDown: return "Day down"
        case .near52WeekHigh: return "Near 52w high"
        case .near52WeekLow: return "Near 52w low"
        }
    }

    var systemImage: String {
        switch self {
        case .priceAbove, .dailyChangeUp, .near52WeekHigh: return "arrow.up.right"
        case .priceBelow, .dailyChangeDown, .near52WeekLow: return "arrow.down.right"
        }
    }
}
