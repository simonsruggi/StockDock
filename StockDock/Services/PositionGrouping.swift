import Foundation

/// One row of the positions table: a symbol held once, or the same symbol held
/// in several portfolios (or lots) merged into an average position.
struct PositionGroup: Identifiable {
    let id: String
    let items: [ValuedHolding]
    let combined: ValuedHolding
    var isGrouped: Bool { items.count > 1 }
    var portfolioCount: Int { Set(items.map(\.portfolioId)).count }
}

enum PositionGrouping {
    /// Longs and shorts of the same symbol stay apart: averaging them would net
    /// two opposite bets into a figure that describes neither.
    static func groups(_ holdings: [ValuedHolding]) -> [PositionGroup] {
        var order: [String] = []
        var bucket: [String: [ValuedHolding]] = [:]
        for h in holdings {
            let key = "\(h.symbol)|\(h.holding.isShort ? "S" : "L")"
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(h)
        }
        return order.compactMap { key in
            guard let items = bucket[key], let first = items.first else { return nil }
            return PositionGroup(id: key, items: items, combined: items.count == 1 ? first : merge(items))
        }
        .sorted { abs($0.combined.value) > abs($1.combined.value) }
    }

    /// Share count summed, price averaged by exposure (shares × leverage).
    static func merge(_ items: [ValuedHolding]) -> ValuedHolding {
        let first = items[0]
        let quantity = items.reduce(0) { $0 + $1.holding.quantity }
        let exposure = items.reduce(0) { $0 + abs($1.holding.quantity) * $1.holding.effectiveLeverage }
        let paid = items.reduce(0) { $0 + $1.holding.avgPrice * abs($1.holding.quantity) * $1.holding.effectiveLeverage }
        let holding = Holding(id: first.holding.id, symbol: first.symbol, quantity: quantity,
                              avgPrice: exposure > 0 ? paid / exposure : 0,
                              purchaseDate: items.compactMap(\.holding.purchaseDate).min())
        return ValuedHolding(id: first.id, portfolioId: first.portfolioId, holding: holding, quote: first.quote,
                             value: items.reduce(0) { $0 + $1.value },
                             cost: items.reduce(0) { $0 + $1.cost },
                             dayChangePercent: first.dayChangePercent, type: first.type,
                             priceRate: first.priceRate, priceCurrency: first.priceCurrency)
    }
}
