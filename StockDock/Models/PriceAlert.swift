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

/// A one-shot price alert for a single symbol. After firing, `isEnabled` is set
/// to false so it does not notify again until the user re-arms it.
struct PriceAlert: Identifiable, Codable, Equatable {
    var id: UUID
    var symbol: String
    var condition: AlertCondition
    /// Absolute price for price conditions; a positive percent for the others.
    var threshold: Double
    var isEnabled: Bool
    var createdAt: Date
    var lastTriggeredAt: Date?

    init(id: UUID = UUID(),
         symbol: String,
         condition: AlertCondition,
         threshold: Double,
         isEnabled: Bool = true,
         createdAt: Date = Date(),
         lastTriggeredAt: Date? = nil) {
        self.id = id
        self.symbol = symbol
        self.condition = condition
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastTriggeredAt = lastTriggeredAt
    }

    /// A new, armed alert on the same symbol (context menu "Duplicate…").
    func duplicate(condition: AlertCondition? = nil, threshold: Double? = nil) -> PriceAlert {
        PriceAlert(symbol: symbol, condition: condition ?? self.condition,
                   threshold: threshold ?? self.threshold)
    }

    /// Alerts split by condition (enum order), each sorted by threshold.
    static func groupedByCondition(_ alerts: [PriceAlert]) -> [(condition: AlertCondition, alerts: [PriceAlert])] {
        AlertCondition.allCases.compactMap { condition in
            let matching = alerts.filter { $0.condition == condition }.sorted { $0.threshold < $1.threshold }
            return matching.isEmpty ? nil : (condition, matching)
        }
    }

    /// Alerts grouped by symbol, groups in first-appearance order; inside a group
    /// sorted by condition then threshold, so ladders of levels read top-down.
    static func groupedBySymbol(_ alerts: [PriceAlert]) -> [(symbol: String, alerts: [PriceAlert])] {
        var order: [String] = []
        var bySymbol: [String: [PriceAlert]] = [:]
        for alert in alerts {
            if bySymbol[alert.symbol] == nil { order.append(alert.symbol) }
            bySymbol[alert.symbol, default: []].append(alert)
        }
        let rank = Dictionary(uniqueKeysWithValues: AlertCondition.allCases.enumerated().map { ($1, $0) })
        return order.map { symbol in
            (symbol, bySymbol[symbol]!.sorted {
                (rank[$0.condition]!, $0.threshold) < (rank[$1.condition]!, $1.threshold)
            })
        }
    }
}

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
