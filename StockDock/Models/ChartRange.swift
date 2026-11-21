import Foundation

/// Chart periods shared by the symbol chart and the portfolio value chart, so
/// the two pickers always offer the same ranges.
enum ChartRange: String, CaseIterable {
    case day = "24H", week = "7D", month = "1M", threeMonths = "3M", sixMonths = "6M",
         ytd = "YTD", year = "1Y", fiveYears = "5Y", all = "All"

    /// Lookback window in days; nil = no fixed window (YTD is bounded by
    /// `cutoff`, All shows the whole series).
    var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 91
        case .sixMonths: return 182
        case .year: return 365
        case .fiveYears: return 1826
        case .ytd, .all: return nil
        }
    }

    /// Hyperliquid candle series for the intraday ranges, which can show the 24/7 hours.
    var candleSpan: HyperliquidCandles.Span? {
        switch self {
        case .day: return .day
        case .week: return .week
        default: return nil
        }
    }

    /// Earliest date the range shows, or nil for the whole series.
    func cutoff(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        if self == .ytd { return calendar.date(from: calendar.dateComponents([.year], from: now)) }
        guard let days else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: now)
    }

    /// 24H uses the 5-minute intraday feed; the rest use daily or coarser closes.
    var isIntraday: Bool { self == .day }

    /// Reaches past the 2-year daily series, so it needs a coarser one.
    var needsLongHistory: Bool { self == .fiveYears || self == .all }

    /// Day + month on the X axis (spans under a year); month + year above.
    var isShortSpan: Bool {
        switch self {
        case .month, .threeMonths, .sixMonths, .ytd: return true
        default: return false
        }
    }

    /// Suffix for the change pill, describing the span it measures.
    var changeLabel: String {
        switch self {
        case .day: return "today"
        case .week: return "past 7d"
        case .ytd: return "this year"
        case .all: return "all-time"
        default: return "past \(rawValue)"
        }
    }

    /// Points from `series` inside the range. YTD keeps the last point before
    /// January 1st: the year's change is measured from last year's final close.
    func slice<T>(_ series: [T], date: (T) -> Date, now: Date = Date()) -> [T] {
        guard let cutoff = cutoff(now: now) else { return series }
        let inRange = series.filter { date($0) >= cutoff }
        if self == .ytd, let base = series.last(where: { date($0) < cutoff }) {
            return [base] + inRange
        }
        return inRange
    }
}
