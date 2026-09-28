import Foundation

/// The kind of portfolio-level notification a user can attach to a single portfolio.
enum PortfolioNotificationMode: String, Codable, CaseIterable {
    /// Fires when the portfolio's daily change crosses each ±`threshold` percent step.
    case dailyPercent
    /// Fires when the portfolio's daily change crosses each ±`threshold` step (preferred currency).
    case dailyAbsolute
    /// Once per day, after `threshold` o'clock (local time): a recap of value + day P&L + top mover.
    case dailySummary
    /// Fires when the total value crosses a new multiple of `threshold` (preferred currency).
    case milestone

    var label: String {
        switch self {
        case .dailyPercent: return "Daily move ≥ %"
        case .dailyAbsolute: return "Daily move ≥ amount"
        case .dailySummary: return "Daily summary"
        case .milestone: return "Value milestone"
        }
    }

    var systemImage: String {
        switch self {
        case .dailyPercent: return "percent"
        case .dailyAbsolute: return "eurosign.circle"
        case .dailySummary: return "calendar.badge.clock"
        case .milestone: return "flag.checkered"
        }
    }

    /// Unit shown next to the threshold field. `currencySymbol` is substituted by the view.
    enum ThresholdKind { case percent, currency, hour }

    var thresholdKind: ThresholdKind {
        switch self {
        case .dailyPercent: return .percent
        case .dailyAbsolute, .milestone: return .currency
        case .dailySummary: return .hour
        }
    }

    var defaultThreshold: Double {
        switch self {
        case .dailyPercent: return 1
        case .dailyAbsolute: return 250
        case .milestone: return 10_000
        case .dailySummary: return 22
        }
    }

    var help: String {
        switch self {
        case .dailyPercent: return "Get pinged once when today's gain or loss first reaches ±this percentage — at most once up and once down per day."
        case .dailyAbsolute: return "Get pinged once when today's gain or loss first reaches ±this amount — at most once up and once down per day."
        case .dailySummary: return "One recap per day after this hour: total value, today's P&L and the biggest mover."
        case .milestone: return "Get pinged when the total value crosses a new multiple of this amount."
        }
    }
}
