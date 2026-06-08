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
        case .dailyPercent: return "Get pinged each time today's gain/loss crosses another step of this percentage."
        case .dailyAbsolute: return "Get pinged each time today's gain/loss crosses another step of this amount."
        case .dailySummary: return "One recap per day after this hour: total value, today's P&L and the biggest mover."
        case .milestone: return "Get pinged when the total value crosses a new multiple of this amount."
        }
    }
}

/// A per-portfolio notification rule. Unlike one-shot `PriceAlert`s these are recurring;
/// `lastStep`/`lastDay` hold the anti-spam state so each event fires at most once.
struct PortfolioNotification: Identifiable, Codable, Equatable {
    var id: UUID
    var mode: PortfolioNotificationMode
    var threshold: Double
    var isEnabled: Bool
    /// Last fired step (dailyPercent/dailyAbsolute, scoped to `lastDay`) or last milestone level.
    var lastStep: Double?
    /// yyyy-MM-dd of the last fire — resets daily steps and gates the daily summary.
    var lastDay: String?

    init(id: UUID = UUID(),
         mode: PortfolioNotificationMode,
         threshold: Double,
         isEnabled: Bool = true,
         lastStep: Double? = nil,
         lastDay: String? = nil) {
        self.id = id
        self.mode = mode
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.lastStep = lastStep
        self.lastDay = lastDay
    }
}

/// Pure, side-effect-free evaluation of portfolio notification conditions.
/// This is the unit under test; the monitor feeds it live metrics and persists the returned state.
enum PortfolioAlertEvaluator {

    /// Threshold-crossing with hysteresis. Returns the new signed step to record when the metric
    /// has crossed into a step not yet notified, otherwise nil.
    /// - Parameters:
    ///   - value: the metric (percent for dailyPercent, currency amount for dailyAbsolute).
    ///   - threshold: step size (> 0).
    ///   - lastStep: the step last notified for the current day (nil if none / new day).
    static func crossingStep(value: Double, threshold: Double, lastStep: Double?) -> Double? {
        guard threshold > 0 else { return nil }
        let step = (value / threshold).rounded(.towardZero)   // signed whole steps
        guard step != 0 else { return nil }                   // within ±1 threshold: nothing crossed
        if let last = lastStep, last == step { return nil }   // already notified this step
        return step
    }

    /// Returns the milestone (a multiple of `step`) the total value currently sits on, when it
    /// differs from `lastMilestone`. Returns nil when nothing new is crossed.
    static func milestoneCrossed(totalValue: Double, step: Double, lastMilestone: Double?) -> Double? {
        guard step > 0, totalValue > 0 else { return nil }
        let milestone = (totalValue / step).rounded(.down) * step
        guard milestone > 0 else { return nil }
        if let last = lastMilestone, last == milestone { return nil }
        return milestone
    }

    /// Daily summary fires once per calendar day, only after the market-close gate.
    static func shouldFireSummary(today: String, lastDay: String?, isAfterClose: Bool) -> Bool {
        isAfterClose && lastDay != today
    }
}
