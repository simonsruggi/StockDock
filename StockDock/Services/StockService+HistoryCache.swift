import Foundation

extension StockService {
    /// The chart series the app keeps per symbol.
    enum HistoryKind: String {
        case daily, max, fiveYears, intraday
    }

    func historyFailed(_ kind: HistoryKind, _ symbol: String) -> Bool {
        failedHistory.contains("\(kind.rawValue):\(symbol)")
    }

    /// Records the outcome of a series request. Writes only on a change, so a
    /// successful refresh does not republish the set.
    func markHistory(_ kind: HistoryKind, _ symbol: String, failed: Bool) {
        let key = "\(kind.rawValue):\(symbol)"
        if failed { if !failedHistory.contains(key) { failedHistory.insert(key) } }
        else if failedHistory.contains(key) { failedHistory.remove(key) }
    }

    /// Drops chart series of symbols no longer in the watchlist or a portfolio
    /// once they are older than 6h — by then they would be re-fetched anyway.
    /// StockDock runs for days, and every symbol opened from search or news
    /// otherwise kept its series in memory until quit.
    func evictStaleHistory(keeping tracked: Set<String>, now: Date = Date()) {
        let maxAge: TimeInterval = 6 * 3600
        func stale(_ fetchedAt: [String: Date], _ symbol: String) -> Bool {
            guard !tracked.contains(symbol) else { return false }
            guard let at = fetchedAt[symbol] else { return true }
            return now.timeIntervalSince(at) > maxAge
        }
        func drop<T>(_ series: [String: T], _ fetchedAt: [String: Date]) -> [String] {
            series.keys.filter { stale(fetchedAt, $0) }
        }
        // Collected first and written only when something goes: every write to a
        // @Published dictionary redraws the views observing the service.
        let daily = drop(priceHistory, priceHistoryFetchedAt)
        if !daily.isEmpty { for s in daily { priceHistory[s] = nil; priceHistoryFetchedAt[s] = nil } }
        let max = drop(priceHistoryMax, priceHistoryMaxAt)
        if !max.isEmpty { for s in max { priceHistoryMax[s] = nil; priceHistoryMaxAt[s] = nil } }
        let five = drop(priceHistory5y, priceHistory5yAt)
        if !five.isEmpty { for s in five { priceHistory5y[s] = nil; priceHistory5yAt[s] = nil } }
        let day = drop(intradayHistory, intradayFetchedAt)
        if !day.isEmpty { for s in day { intradayHistory[s] = nil; intradayFetchedAt[s] = nil } }
        let week = drop(intradayWeek, intradayWeekAt)
        if !week.isEmpty { for s in week { intradayWeek[s] = nil; intradayWeekAt[s] = nil } }
        let ext = drop(intradayExtended, intradayExtendedAt)
        if !ext.isEmpty { for s in ext { intradayExtended[s] = nil; intradayExtendedAt[s] = nil } }
        for (range, bySymbol) in sparkSeries {
            let rangeStale = sparkSeriesAt[range].map { now.timeIntervalSince($0) > maxAge } ?? true
            guard rangeStale else { continue }
            let gone = bySymbol.keys.filter { !tracked.contains($0) }
            if !gone.isEmpty { for s in gone { sparkSeries[range]?[s] = nil } }
        }
        let failed = failedHistory.filter { key in
            tracked.contains(String(key.split(separator: ":", maxSplits: 1).last ?? ""))
        }
        if failed != failedHistory { failedHistory = failed }
    }
}
