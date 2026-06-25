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

/// A per-portfolio notification rule. Unlike one-shot `PriceAlert`s these are recurring;
/// `lastStep`/`lastDay` hold the anti-spam state so each event fires at most once.
struct PortfolioNotification: Identifiable, Codable, Equatable {
    var id: UUID
    var mode: PortfolioNotificationMode
    var threshold: Double
    var isEnabled: Bool
    /// High-water mark on the **up** side: highest positive step notified today
    /// (dailyPercent/dailyAbsolute, scoped to `lastDay`) or the highest milestone reached.
    var lastStepUp: Double?
    /// High-water mark on the **down** side: lowest negative step notified today
    /// (scoped to `lastDay`) or the lowest milestone reached.
    var lastStepDown: Double?
    /// yyyy-MM-dd of the last fire — resets daily steps and gates the daily summary.
    var lastDay: String?

    init(id: UUID = UUID(),
         mode: PortfolioNotificationMode,
         threshold: Double,
         isEnabled: Bool = true,
         lastStepUp: Double? = nil,
         lastStepDown: Double? = nil,
         lastDay: String? = nil) {
        self.id = id
        self.mode = mode
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.lastStepUp = lastStepUp
        self.lastStepDown = lastStepDown
        self.lastDay = lastDay
    }
}

/// Pure, side-effect-free evaluation of portfolio notification conditions.
/// This is the unit under test; the monitor feeds it live metrics and persists the returned state.
enum PortfolioAlertEvaluator {

    /// Per-direction **once-a-day** gate. Fires `+1` the first time today's value reaches
    /// `+threshold`, and `-1` the first time it reaches `-threshold`; everything afterwards on
    /// that side stays silent until the next calendar day. This caps a trending or oscillating
    /// day at one up + one down notification — no per-step stream.
    /// - Parameters:
    ///   - value: the metric (percent for dailyPercent, currency amount for dailyAbsolute).
    ///   - threshold: trigger magnitude (> 0).
    ///   - lastUp: non-nil once the up side has already fired today (caller resets each new day).
    ///   - lastDown: non-nil once the down side has already fired today.
    static func crossingStep(value: Double, threshold: Double, lastUp: Double?, lastDown: Double?) -> Double? {
        guard threshold > 0 else { return nil }
        if value >= threshold {
            return lastUp == nil ? 1 : nil      // first up-crossing of the day
        } else if value <= -threshold {
            return lastDown == nil ? -1 : nil   // first down-crossing of the day
        }
        return nil                              // within ±threshold: nothing to announce
    }

    /// Returns the milestone (a multiple of `step`) to announce, using **high-water bounds** so a
    /// value oscillating around a boundary doesn't re-announce levels it has already passed.
    /// Fires only when the floored milestone sits strictly above `highest` (a new high) or strictly
    /// below `lowest` (a new low). On the very first observation (`highest`/`lowest` nil) the caller
    /// is expected to prime the bounds silently.
    static func milestoneCrossed(totalValue: Double, step: Double, highest: Double?, lowest: Double?) -> Double? {
        guard step > 0, totalValue > 0 else { return nil }
        let milestone = (totalValue / step).rounded(.down) * step
        guard milestone > 0 else { return nil }
        if let high = highest, milestone > high { return milestone }   // new high
        if let low = lowest, milestone < low { return milestone }      // new low
        if highest == nil && lowest == nil { return milestone }        // first observation (caller primes)
        return nil
    }

    /// Daily summary fires once per calendar day, only after the market-close gate.
    static func shouldFireSummary(today: String, lastDay: String?, isAfterClose: Bool) -> Bool {
        isAfterClose && lastDay != today
    }
}
