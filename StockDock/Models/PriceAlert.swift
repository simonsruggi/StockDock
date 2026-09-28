import Foundation

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
