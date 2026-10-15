import Foundation

/// Estimates a past portfolio-value curve from each holding's real daily price
/// history times the *current* position — so the Overview chart shows a trend on
/// day one, before real daily snapshots accumulate.
///
/// This is explicitly an estimate (labelled as such in the UI): it assumes each
/// position was held at its current size since its purchase date, and uses the
/// current FX rate. Real snapshots, once present, take precedence.
enum PortfolioBackfill {
    static func series(holdings: [Holding],
                       historyBySymbol: [String: [PricePoint]],
                       rateBySymbol: [String: Double]) -> [ValuePoint] {
        var historyFor: [String: [PricePoint]] = [:]
        for holding in holdings {
            guard let points = historyBySymbol[holding.symbol], !points.isEmpty else { return [] }
            historyFor[holding.symbol] = points.sorted { $0.date < $1.date }
        }

        // Each position counts only from the day it was bought, and the curve as a
        // whole starts at the oldest purchase. Without this, "All" projects today's
        // share counts back to the earliest quote Yahoo has and draws a portfolio
        // decades older than it is (a 2026 position charted from 2005).
        // Holdings with no purchase date (imported, or saved before the field
        // existed) keep the old behaviour: valued across the whole window.
        let ownedFrom: [UUID: Date] = holdings.reduce(into: [:]) { acc, holding in
            if let date = holding.purchaseDate { acc[holding.id] = Calendar.current.startOfDay(for: date) }
        }

        // The curve starts once every counted position has a price. Each symbol
        // then keeps its last close until its next bar: symbols from different
        // exchanges print at different times (Milan 09:00, New York 15:30 CET) and
        // on different holidays, so requiring the same timestamp for all of them
        // left 24H/7D empty for a mixed portfolio.
        var start = ownedFrom.values.min() ?? .distantPast
        for holding in holdings {
            guard let first = historyFor[holding.symbol]?.first?.date else { continue }
            if let from = ownedFrom[holding.id], first <= from { continue }
            start = max(start, first)
        }

        let dates = Set(historyFor.values.flatMap { $0.map(\.date) }).filter { $0 >= start }.sorted()
        guard !dates.isEmpty else { return [] }

        var cursor: [String: Int] = [:]
        var lastClose: [String: Double] = [:]
        return dates.map { date in
            for (symbol, points) in historyFor {
                var i = cursor[symbol] ?? 0
                while i < points.count, points[i].date <= date {
                    lastClose[symbol] = points[i].close
                    i += 1
                }
                cursor[symbol] = i
            }
            var total = 0.0
            for holding in holdings {
                if let from = ownedFrom[holding.id], date < from { continue }
                let close = lastClose[holding.symbol] ?? 0
                let rate = rateBySymbol[holding.symbol] ?? 1
                total += close * holding.quantity * holding.effectiveLeverage * rate
            }
            return ValuePoint(date: date, value: total)
        }
    }
}
