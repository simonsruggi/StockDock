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
        // Per-symbol date → close lookup, and the set of dates present for ALL
        // holdings (a day missing any symbol would understate the total).
        var closeBySymbol: [String: [Date: Double]] = [:]
        for holding in holdings {
            guard let points = historyBySymbol[holding.symbol], !points.isEmpty else { return [] }
            closeBySymbol[holding.symbol] = Dictionary(points.map { ($0.date, $0.close) }, uniquingKeysWith: { a, _ in a })
        }
        guard let first = holdings.first,
              let firstDates = closeBySymbol[first.symbol]?.keys else { return [] }

        var commonDates = Set(firstDates)
        for holding in holdings.dropFirst() {
            commonDates.formIntersection(Set(closeBySymbol[holding.symbol]?.keys ?? [:].keys))
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
        if let start = ownedFrom.values.min() {
            commonDates = commonDates.filter { $0 >= start }
        }
        guard !commonDates.isEmpty else { return [] }

        return commonDates.sorted().map { date in
            var total = 0.0
            for holding in holdings {
                if let from = ownedFrom[holding.id], date < from { continue }
                let close = closeBySymbol[holding.symbol]?[date] ?? 0
                let rate = rateBySymbol[holding.symbol] ?? 1
                total += close * holding.quantity * holding.effectiveLeverage * rate
            }
            return ValuePoint(date: date, value: total)
        }
    }
}
