import Foundation

/// Regular trading window of a symbol's exchange, from Yahoo's chart
/// `currentTradingPeriod` (it already accounts for half days).
struct RegularSession: Equatable {
    let start: Date
    let end: Date
    let fetchedAt: Date
}

extension StockService {
    private static let sessionRefreshInterval: TimeInterval = 3600
    /// A window this far from `now` belongs to another trading day and is ignored.
    private static let sessionValidityMargin: TimeInterval = 12 * 3600

    /// The regular session exists only between open and close. Yahoo occasionally
    /// labels a quote REGULAR outside that window (e.g. the previous close replayed
    /// during pre-market), so a REGULAR state outside it becomes PRE or POST.
    /// Without a window valid for `now`, Yahoo's state is kept.
    nonisolated static func clampToRegularSession(_ state: String, session: RegularSession?, now: Date) -> String {
        guard state == "REGULAR", let session,
              now > session.start.addingTimeInterval(-sessionValidityMargin),
              now < session.end.addingTimeInterval(sessionValidityMargin) else { return state }
        if now < session.start { return "PRE" }
        if now >= session.end { return "POST" }
        return state
    }

    func clampedMarketState(_ state: String, symbol: String) -> String {
        Self.clampToRegularSession(state, session: regularSessions[symbol], now: Date())
    }

    func storeRegularSession(_ periods: YahooChartResponse.TradingPeriods?, symbol: String) {
        guard let regular = periods?.regular, regular.end > regular.start else { return }
        regularSessions[symbol] = RegularSession(
            start: Date(timeIntervalSince1970: TimeInterval(regular.start)),
            end: Date(timeIntervalSince1970: TimeInterval(regular.end)),
            fetchedAt: Date())
    }

    /// Fetches the trading window for symbols that have none or an old one.
    func refreshRegularSessions(symbols: [String]) async {
        let now = Date()
        let due = symbols.filter { sym in
            guard let s = regularSessions[sym] else { return true }
            return now.timeIntervalSince(s.fetchedAt) > Self.sessionRefreshInterval
        }
        guard !due.isEmpty else { return }

        let session = self.session
        let results = await withTaskGroup(of: (String, YahooChartResponse.TradingPeriods?).self) { group in
            for symbol in due {
                group.addTask {
                    let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
                    guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d"),
                          let (data, _) = try? await session.data(from: url),
                          let decoded = try? JSONDecoder().decode(YahooChartResponse.self, from: data) else { return (symbol, nil) }
                    return (symbol, decoded.chart.result?.first?.meta.currentTradingPeriod)
                }
            }
            var out: [(String, YahooChartResponse.TradingPeriods?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (symbol, periods) in results {
            storeRegularSession(periods, symbol: symbol)
        }
    }
}

extension StockQuote {
    func withMarketState(_ state: String) -> StockQuote {
        guard state != marketState else { return self }
        return StockQuote(
            symbol: symbol, name: name, price: price, change: change, changePercent: changePercent,
            currency: currency, marketState: state, dayHigh: dayHigh, dayLow: dayLow,
            fiftyTwoWeekHigh: fiftyTwoWeekHigh, fiftyTwoWeekLow: fiftyTwoWeekLow,
            preMarketPrice: preMarketPrice, preMarketChange: preMarketChange, preMarketChangePercent: preMarketChangePercent,
            postMarketPrice: postMarketPrice, postMarketChange: postMarketChange, postMarketChangePercent: postMarketChangePercent)
    }
}
