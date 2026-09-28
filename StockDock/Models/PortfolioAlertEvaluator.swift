import Foundation

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
