import Foundation

/// Pure, side-effect-free evaluation of alert conditions. This is the unit under test;
/// the app feeds it live quote values and reacts to the boolean result.
enum AlertEvaluator {

    /// Core evaluation over primitive inputs (no model dependencies, fully testable).
    /// - Returns: true when the condition is met. A disabled alert never fires.
    static func shouldFire(condition: AlertCondition,
                           threshold: Double,
                           isEnabled: Bool,
                           price: Double,
                           changePercent: Double,
                           fiftyTwoWeekHigh: Double?,
                           fiftyTwoWeekLow: Double?) -> Bool {
        guard isEnabled, price > 0 else { return false }

        switch condition {
        case .priceAbove:
            return price >= threshold
        case .priceBelow:
            return price <= threshold
        case .dailyChangeUp:
            return changePercent >= threshold
        case .dailyChangeDown:
            return changePercent <= -threshold
        case .near52WeekHigh:
            guard let high = fiftyTwoWeekHigh, high > 0 else { return false }
            return price >= high * (1 - threshold / 100)
        case .near52WeekLow:
            guard let low = fiftyTwoWeekLow, low > 0 else { return false }
            return price <= low * (1 + threshold / 100)
        }
    }

    /// Convenience over a live `PriceAlert` + `StockQuote`. Uses `alertPrice`, which
    /// reflects extended-hours moves but is nil during PRE/POST before the real
    /// extended-hours price arrives — so alerts never fire against the stale
    /// previous regular close.
    static func shouldFire(_ alert: PriceAlert, quote: StockQuote) -> Bool {
        guard let price = quote.alertPrice else { return false }
        return shouldFire(condition: alert.condition,
                          threshold: alert.threshold,
                          isEnabled: alert.isEnabled,
                          price: price,
                          changePercent: quote.changePercent,
                          fiftyTwoWeekHigh: quote.fiftyTwoWeekHigh,
                          fiftyTwoWeekLow: quote.fiftyTwoWeekLow)
    }

    /// Compact summary shown under the symbol header, e.g. "Above $200.00".
    static func describeShort(_ alert: PriceAlert, currencySymbol: String) -> String {
        switch alert.condition.thresholdKind {
        case .price:
            return "\(alert.condition.shortLabel) \(currencySymbol)\(StorageService.formatNumber(alert.threshold, decimals: 2))"
        case .percent:
            switch alert.condition {
            case .near52WeekHigh, .near52WeekLow:
                return "\(alert.condition.shortLabel) (\u{2264} \(String(format: "%.1f", alert.threshold))%)"
            default:
                return "\(alert.condition.shortLabel) \(String(format: "%.1f", alert.threshold))%"
            }
        }
    }

    /// Human-readable summary, e.g. "Price rises above 200.00" — used in the UI.
    static func describe(_ alert: PriceAlert, currencySymbol: String) -> String {
        switch alert.condition.thresholdKind {
        case .price:
            return "\(alert.condition.label) \(currencySymbol)\(StorageService.formatNumber(alert.threshold, decimals: 2))"
        case .percent:
            switch alert.condition {
            case .near52WeekHigh, .near52WeekLow:
                return "\(alert.condition.label) (\u{2264} \(String(format: "%.1f", alert.threshold))%)"
            default:
                return "\(alert.condition.label) \(String(format: "%.1f", alert.threshold))%"
            }
        }
    }
}
