import Foundation

/// What one symbol did to the portfolio over the selected range.
struct PeriodMove: Identifiable {
    var id: String { symbol }
    let symbol: String
    let name: String
    /// Money gained or lost over the range, in the preferred currency.
    let value: Double
    /// What the position was worth at the start of the range (unsigned).
    let base: Double
    var percent: Double { base >= 0.01 ? value / base * 100 : 0 }
}

enum PeriodMovers {
    /// Per-symbol contribution between `cutoff` and now. A position bought inside
    /// the range starts from its purchase price, not from zero: the estimated
    /// curve counts a new buy as a jump in value, which is money moved in, not
    /// money made.
    static func moves(holdings: [ValuedHolding],
                      history: [String: [PricePoint]],
                      since cutoff: Date,
                      livePrice: (StockQuote) -> Double,
                      rate: (String) -> Double) -> [PeriodMove] {
        var value: [String: Double] = [:]
        var base: [String: Double] = [:]
        var names: [String: String] = [:]
        for h in holdings {
            let start: Double
            if let bought = h.holding.purchaseDate, bought > cutoff {
                start = h.holding.avgPrice
            } else if let price = startPrice(history[h.symbol] ?? [], at: cutoff) {
                start = price
            } else {
                continue
            }
            let fx = rate(h.quote.currency)
            let exposure = h.holding.quantity * h.holding.effectiveLeverage
            value[h.symbol, default: 0] += (livePrice(h.quote) - start) * exposure * fx
            base[h.symbol, default: 0] += abs(start * exposure * fx)
            names[h.symbol] = h.name
        }
        return value.map { symbol, v in
            PeriodMove(symbol: symbol, name: names[symbol] ?? symbol, value: v, base: base[symbol] ?? 0)
        }
        .sorted { abs($0.value) > abs($1.value) }
    }

    /// The close in force at `cutoff`, or the first one after it when the
    /// history starts later (a 7D intraday feed covers five sessions).
    static func startPrice(_ points: [PricePoint], at cutoff: Date) -> Double? {
        let sorted = points.sorted { $0.date < $1.date }
        return sorted.last(where: { $0.date <= cutoff })?.close ?? sorted.first?.close
    }

    /// Range total: summed contributions over the summed starting values.
    static func total(_ moves: [PeriodMove]) -> (value: Double, percent: Double)? {
        guard !moves.isEmpty else { return nil }
        let value = moves.reduce(0) { $0 + $1.value }
        let base = moves.reduce(0) { $0 + $1.base }
        return (value, base >= 0.01 ? value / base * 100 : 0)
    }
}
