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
/// This is explicitly an estimate (labelled as such in the UI): it assumes the
/// current holdings were held over the whole window and uses the current FX rate.
/// Real snapshots, once present, take precedence.
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
        guard !commonDates.isEmpty else { return [] }

        return commonDates.sorted().map { date in
            var total = 0.0
            for holding in holdings {
                let close = closeBySymbol[holding.symbol]?[date] ?? 0
                let rate = rateBySymbol[holding.symbol] ?? 1
                total += close * holding.quantity * holding.effectiveLeverage * rate
            }
            return ValuePoint(date: date, value: total)
        }
    }
}
