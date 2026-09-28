import Foundation

extension StockService {
    /// Loads (or refreshes after ~1h) one year of daily closes for the detail
    /// chart. Real Yahoo history — the portfolio value chart intentionally has no
    /// backfill, but a single symbol's price history is accurate data.
    func ensurePriceHistory(for symbol: String) async {
        if let at = priceHistoryFetchedAt[symbol],
           Date().timeIntervalSince(at) < 3600,
           priceHistory[symbol]?.isEmpty == false { return }
        // range=2y keeps FULL daily resolution (Yahoo downsamples 1d+max to coarse
        // data, which starves the 7D/1M ranges). "All" uses the monthly series below.
        guard let points = await chartPoints(for: symbol, query: "interval=1d&range=2y") else { return }
        priceHistory[symbol] = points
        priceHistoryFetchedAt[symbol] = Date()
    }

    /// Monthly closes over the full available history, for the "All" range. Cached ~6h.
    func ensurePriceHistoryMax(for symbol: String) async {
        if let at = priceHistoryMaxAt[symbol],
           Date().timeIntervalSince(at) < 21600,
           priceHistoryMax[symbol]?.isEmpty == false { return }
        guard let points = await chartPoints(for: symbol, query: "interval=1mo&range=max") else { return }
        priceHistoryMax[symbol] = points
        priceHistoryMaxAt[symbol] = Date()
    }

    /// Loads (or refreshes after ~5min) one trading day of 5-minute closes for
    /// the "1D" chart range.
    func ensureIntraday(for symbol: String) async {
        if let at = intradayFetchedAt[symbol],
           Date().timeIntervalSince(at) < 300,
           intradayHistory[symbol]?.isEmpty == false { return }
        // Two days, not one: `range=1d` is empty until today's session prints, so
        // before the open (and all weekend) the 24H chart had nothing to draw and
        // fell through to the "no history yet" placeholder. `lastSession` keeps
        // the most recent session that actually traded.
        guard let raw = await chartPoints(for: symbol, query: "interval=5m&range=2d") else { return }
        let points = PriceHistory.lastSession(raw)
        guard !points.isEmpty else { return }
        intradayHistory[symbol] = points
        intradayFetchedAt[symbol] = Date()
    }

    /// Hourly closes over ~7 days for the "7D" range. Cached ~15min.
    func ensureIntradayWeek(for symbol: String) async {
        if let at = intradayWeekAt[symbol],
           Date().timeIntervalSince(at) < 900,
           intradayWeek[symbol]?.isEmpty == false { return }
        guard let points = await chartPoints(for: symbol, query: "interval=60m&range=7d") else { return }
        intradayWeek[symbol] = points
        intradayWeekAt[symbol] = Date()
    }

    /// Batched sparkline history: one Yahoo `spark` request fills 1-month daily
    /// closes for MANY symbols at once (instead of one request per watchlist row).
    /// Cached ~10min. Only fills symbols missing recent daily history.
    func ensureSparklines(for symbols: [String]) async {
        if let at = sparkFetchedAt, Date().timeIntervalSince(at) < 600 { return }
        let missing = symbols.filter { (priceHistory[$0]?.isEmpty ?? true) }
        guard !missing.isEmpty else { sparkFetchedAt = Date(); return }
        let joined = missing.joined(separator: ",")
        let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? joined
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/spark?symbols=\(encoded)&range=1mo&interval=1d") else { return }
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooSparkResponse.self, from: data)
            for entry in response.spark.result ?? [] {
                guard let r = entry.response.first else { continue }
                let points = PriceHistory.points(timestamps: r.timestamp ?? [],
                                                 closes: r.indicators?.quote?.first?.close ?? [])
                if !points.isEmpty, priceHistory[entry.symbol]?.isEmpty ?? true {
                    priceHistory[entry.symbol] = points
                    priceHistoryFetchedAt[entry.symbol] = Date()
                }
            }
            sparkFetchedAt = Date()
        } catch {
        }
    }

    /// Closes from the v8 chart endpoint for one symbol, or nil when the
    /// request fails or returns no usable point. Failures are non-fatal: the
    /// chart keeps its placeholder until the next attempt.
    private func chartPoints(for symbol: String, query: String) async -> [PricePoint]? {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?\(query)") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = response.chart.result?.first else { return nil }
            let points = PriceHistory.points(timestamps: result.timestamp ?? [],
                                             closes: result.indicators?.quote?.first?.close ?? [])
            return points.isEmpty ? nil : points
        } catch {
            return nil
        }
    }
}
