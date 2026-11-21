import Foundation

/// Value, cost and P&L of one or more lots of the same symbol, in the preferred
/// currency. Each lot keeps its own cost rate (the FX of its purchase), so a
/// merged position adds up to exactly the sum of its lots.
struct HoldingValues {
    let value: Double
    let cost: Double
    let pnl: Double
    var pnlPercent: Double { abs(cost) >= 0.01 ? pnl / abs(cost) * 100 : 0 }

    @MainActor
    init(_ lots: [Holding], quote: StockQuote, price: Double, stockService: StockService, storageService: StorageService) {
        let rate = stockService.rate(from: quote.currency)
        value = lots.reduce(0) { $0 + $1.marketValue(currentPrice: price) * rate }
        cost = lots.reduce(0) { $0 + $1.costBasisLocal * stockService.costRate(for: $1, currency: quote.currency) }
        pnl = storageService.afterTax(value - cost)
    }

    /// Shares summed; price averaged by exposure (shares × leverage), like the desktop.
    static func merged(_ lots: [Holding]) -> Holding {
        let first = lots[0]
        guard lots.count > 1 else { return first }
        let quantity = lots.reduce(0) { $0 + $1.quantity }
        let exposure = lots.reduce(0) { $0 + abs($1.quantity) * $1.effectiveLeverage }
        let paid = lots.reduce(0) { $0 + $1.avgPrice * abs($1.quantity) * $1.effectiveLeverage }
        var holding = Holding(id: first.id, symbol: first.symbol, quantity: quantity,
                              avgPrice: exposure > 0 ? paid / exposure : 0,
                              purchaseDate: lots.compactMap(\.purchaseDate).min())
        holding.leverage = first.leverage
        return holding
    }

    /// Lots grouped by symbol, longs and shorts apart, in the order they first appear.
    static func groups(_ holdings: [Holding]) -> [[Holding]] {
        var order: [String] = []
        var bucket: [String: [Holding]] = [:]
        for h in holdings {
            let key = "\(h.symbol)|\(h.isShort ? "S" : "L")"
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(h)
        }
        return order.compactMap { bucket[$0] }
    }
}
