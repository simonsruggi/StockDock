import Foundation

/// A reconstructed point on the estimated portfolio value curve.
struct ValuePoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

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

/// Change of a drawn value curve over its own span — the delta between its first
/// and last points. Drives the hero pill so it reflects the *selected* period
/// (24H/7D/1M/…) instead of always showing the day-over-day change.
enum PortfolioPeriodChange {
    /// Absolute change (last − first) over the series, or nil if under 2 points.
    static func value(_ points: [ValuePoint]) -> Double? {
        guard let first = points.first?.value, let last = points.last?.value,
              points.count >= 2 else { return nil }
        return last - first
    }

    /// Percentage change vs the first point, or nil if the span is degenerate
    /// (fewer than 2 points, or a starting value too close to zero to divide by).
    static func percent(_ points: [ValuePoint]) -> Double? {
        guard let first = points.first?.value, let last = points.last?.value,
              points.count >= 2, abs(first) >= 0.01 else { return nil }
        return (last - first) / abs(first) * 100
    }
}
