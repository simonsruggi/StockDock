import Foundation

/// The watchlist's Trend column uses the symbol chart's ranges, and both share
/// one remembered selection (`StorageService.lastSymbolChartRange`).
typealias SymbolChartRange = ChartRange

extension ChartRange {
    /// Query for the batched `/v8/finance/spark` request: one per range fills
    /// every watchlist row. Same data as the symbol chart: 5-minute bars for 24H,
    /// daily closes (fetched with headroom, then cut by `sparkTrim`) up to 1Y,
    /// weekly for 5Y and monthly for All.
    var sparkQuery: String {
        switch self {
        // Two days, like `ensureIntraday`: range=1d is empty before the open and on weekends.
        case .day: return "range=2d&interval=5m"
        case .week, .month: return "range=3mo&interval=1d"
        case .threeMonths, .sixMonths: return "range=1y&interval=1d"
        // Not range=ytd: YTD needs last year's final close as its baseline, and
        // 2y still reaches it when the year ended on a weekend.
        case .ytd, .year: return "range=2y&interval=1d"
        case .fiveYears: return "range=5y&interval=1wk"
        case .all: return "range=max&interval=1mo"
        }
    }

    /// The series the symbol chart would draw for this range.
    func sparkTrim(_ points: [PricePoint]) -> [PricePoint] {
        isIntraday ? PriceHistory.lastSession(points) : slice(points, date: \.date)
    }

    /// Intraday data moves; longer ranges barely change within a session.
    var sparkCacheSeconds: TimeInterval { isIntraday ? 300 : 1800 }
}
