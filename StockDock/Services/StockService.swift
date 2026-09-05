import Foundation

@MainActor
class StockService: ObservableObject {
    static let shared = StockService()

    @Published var quotes: [String: StockQuote] = [:]
    @Published var isLoading = false
    @Published var exchangeRates: [String: Double] = [:]  // e.g. "USDEUR" -> 0.92 (rate to preferred currency)
    @Published var historicalRates: [String: Double] = [:]  // e.g. "USDEUR:1704067200" -> 0.9045 (rate at date)
    @Published var news: [NewsArticle] = []
    @Published var isLoadingNews = false
    /// Daily close history per symbol (~2 years, full daily resolution) for the
    /// 7D/1M/1Y ranges. Cached ~1h.
    @Published var priceHistory: [String: [PricePoint]] = [:]
    /// Monthly close history over the full available range, for the "All" range.
    /// Cached ~6h. (Yahoo downsamples daily+max to coarse data, so "All" needs its
    /// own monthly series and the shorter ranges need the daily 2y series.)
    @Published var priceHistoryMax: [String: [PricePoint]] = [:]
    /// Intraday (5-minute) closes for the "24H" chart range. Cached ~5min.
    @Published var intradayHistory: [String: [PricePoint]] = [:]
    /// Hourly closes over ~7 days for the "7D" chart range. Cached ~15min.
    @Published var intradayWeek: [String: [PricePoint]] = [:]

    private let session: URLSession
    private var crumb: String?
    private var lastNewsFetch: Date?
    private var priceHistoryFetchedAt: [String: Date] = [:]
    private var priceHistoryMaxAt: [String: Date] = [:]
    private var intradayFetchedAt: [String: Date] = [:]
    private var intradayWeekAt: [String: Date] = [:]
    private var sparkFetchedAt: Date?

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
        ]
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = .shared
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    static func collectSymbols(storageService: StorageService) -> Set<String> {
        var syms = Set(storageService.watchlist)
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                syms.insert(holding.symbol)
            }
        }
        return syms
    }

    /// Full refresh: quotes (REST) + exchange rates. Use only at startup or when WSS is down.
    func refreshAll(storageService: StorageService) async {
        let allSymbols = Self.collectSymbols(storageService: storageService)
        guard !allSymbols.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        // Evict quotes for symbols no longer tracked
        let staleKeys = Set(quotes.keys).subtracting(allSymbols)
        for key in staleKeys { quotes.removeValue(forKey: key) }

        await fetchQuotes(symbols: Array(allSymbols))
        await refreshExchangeRates(storageService: storageService)
    }

    /// Refresh only exchange rates (current + historical). Called periodically while WSS handles quotes.
    func refreshExchangeRates(storageService: StorageService) async {
        let allSymbols = Self.collectSymbols(storageService: storageService)
        guard !allSymbols.isEmpty else { return }

        // Fetch exchange rates for all stock currencies toward both target currencies
        let preferredCurrency = storageService.preferredCurrency
        let priceCurrency = storageService.stockPriceCurrency

        // Collect all pairs we need: (from, to)
        var pairs = Set<String>() // "FROMTO" keys
        for symbol in allSymbols {
            guard let quote = quotes[symbol] else { continue }
            if quote.currency != preferredCurrency {
                pairs.insert("\(quote.currency)|\(preferredCurrency)")
            }
            if !priceCurrency.isEmpty && quote.currency != priceCurrency {
                pairs.insert("\(quote.currency)|\(priceCurrency)")
            }
        }

        // Evict exchange rates no longer needed
        let neededRateKeys = Set(pairs.compactMap { pair -> String? in
            let parts = pair.split(separator: "|")
            guard parts.count >= 2 else { return nil }
            return "\(parts[0])\(parts[1])"
        })
        let staleRateKeys = Set(exchangeRates.keys).subtracting(neededRateKeys)
        for key in staleRateKeys { exchangeRates.removeValue(forKey: key) }

        await withTaskGroup(of: Void.self) { group in
            for pair in pairs {
                let parts = pair.split(separator: "|")
                guard parts.count >= 2 else { continue }
                let from = String(parts[0])
                let to = String(parts[1])
                group.addTask { [weak self] in
                    await self?.fetchExchangeRate(from: from, to: to)
                }
            }
        }

        // Fetch historical rates for holdings with purchase date — skip if already cached
        var neededHistoricalKeys = Set<String>()
        var historicalKeysToFetch = Set<String>()
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                guard let purchaseDate = holding.purchaseDate,
                      let quote = quotes[holding.symbol],
                      quote.currency != preferredCurrency
                else { continue }
                let dayStart = Calendar.current.startOfDay(for: purchaseDate)
                let ts = Int(dayStart.timeIntervalSince1970)
                let cacheKey = "\(quote.currency)\(preferredCurrency):\(ts)"
                neededHistoricalKeys.insert(cacheKey)
                if historicalRates[cacheKey] == nil {
                    historicalKeysToFetch.insert("\(quote.currency)|\(preferredCurrency)|\(ts)")
                }
            }
        }

        // Evict historical rates no longer needed
        let staleHistKeys = Set(historicalRates.keys).subtracting(neededHistoricalKeys)
        for key in staleHistKeys { historicalRates.removeValue(forKey: key) }

        await withTaskGroup(of: Void.self) { group in
            for key in historicalKeysToFetch {
                let parts = key.split(separator: "|")
                guard parts.count == 3,
                      let ts = Int(parts[2])
                else { continue }
                let from = String(parts[0])
                let to = String(parts[1])
                group.addTask { [weak self] in
                    await self?.fetchHistoricalExchangeRate(from: from, to: to, dateTimestamp: ts)
                }
            }
        }
    }

    func fetchQuotes(symbols: [String]) async {
        guard !symbols.isEmpty else { return }

        // Try v7 batch quote first (single HTTP call, live extended hours)
        if await fetchQuotesV7(symbols: symbols) {
            return
        }

        // Fallback: fetch each symbol via v8 chart API
        await withTaskGroup(of: Void.self) { group in
            for symbol in symbols {
                group.addTask { [weak self] in
                    await self?.fetchSingleQuote(symbol: symbol)
                }
            }
        }
    }

    // MARK: - v7 Quote API (batch, live extended hours)

    private func fetchCrumb() async -> Bool {
        // Step 1: GET fc.yahoo.com to collect cookies
        guard let cookieUrl = URL(string: "https://fc.yahoo.com") else { return false }
        _ = try? await session.data(from: cookieUrl)

        // Step 2: GET crumb using the cookies
        guard let crumbUrl = URL(string: "https://query2.finance.yahoo.com/v1/test/getcrumb") else { return false }
        do {
            let (data, response) = try await session.data(from: crumbUrl)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return false }
            guard let crumbValue = String(data: data, encoding: .utf8), !crumbValue.isEmpty else { return false }
            self.crumb = crumbValue
            return true
        } catch {
            return false
        }
    }

    private func fetchQuotesV7(symbols: [String], retried: Bool = false) async -> Bool {
        if crumb == nil {
            guard await fetchCrumb() else { return false }
        }

        guard let crumb = crumb else { return false }

        let joined = symbols.map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }.joined(separator: ",")
        let crumbEncoded = crumb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? crumb
        guard let url = URL(string: "https://query2.finance.yahoo.com/v7/finance/quote?symbols=\(joined)&crumb=\(crumbEncoded)") else { return false }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResp = response as? HTTPURLResponse else { return false }

            if httpResp.statusCode == 401 {
                guard !retried else { return false }
                self.crumb = nil
                guard await fetchCrumb() else { return false }
                return await fetchQuotesV7(symbols: symbols, retried: true)
            }

            guard httpResp.statusCode == 200 else { return false }

            let parsed: V7ParseResult
            do {
                parsed = try Self.parseV7Response(data)
            } catch {
                return false
            }
            guard !parsed.quotes.isEmpty else { return false }

            for quote in parsed.quotes {
                quotes[quote.symbol] = quote
            }
            for (symbol, type) in parsed.types {
                StorageService.shared.setType(type, for: symbol)
            }

            return true
        } catch {
            return false
        }
    }

    /// Parsed output of a Yahoo v7 batch-quote response.
    struct V7ParseResult {
        let quotes: [StockQuote]
        let types: [String: String]  // symbol -> Yahoo quoteType
    }

    /// Decode and map a Yahoo v7 `/finance/quote` batch response into `StockQuote`s.
    /// Entries without a `regularMarketPrice` (delisted/suspended tickers come back
    /// partial) are skipped rather than making the whole batch throw — so one bad
    /// symbol can no longer drop live quotes for every other symbol. Pure and
    /// `nonisolated` so it is unit-testable without running the service.
    nonisolated static func parseV7Response(_ data: Data) throws -> V7ParseResult {
        let decoded = try JSONDecoder().decode(YahooV7Response.self, from: data)
        guard let results = decoded.quoteResponse.result else {
            return V7ParseResult(quotes: [], types: [:])
        }

        var quotes: [StockQuote] = []
        var types: [String: String] = [:]

        for q in results {
            guard let price = q.regularMarketPrice else { continue }
            let previousClose = q.regularMarketPreviousClose ?? price
            let change = q.regularMarketChange ?? (price - previousClose)
            let changePercent = q.regularMarketChangePercent ?? (previousClose > 0 ? (change / previousClose) * 100 : 0)

            // Normalize marketState
            let rawState = q.marketState ?? "CLOSED"
            let marketState: String
            switch rawState {
            case "REGULAR": marketState = "REGULAR"
            case "PRE": marketState = "PRE"
            case "POST": marketState = "POST"
            default: marketState = "CLOSED" // PREPRE, POSTPOST, etc.
            }

            let preChg: Double? = if let pm = q.preMarketPrice { pm - price } else { nil }
            let prePct: Double? = if let ch = preChg, price > 0 { (ch / price) * 100 } else { nil }
            let postChg: Double? = if let pm = q.postMarketPrice { pm - price } else { nil }
            let postPct: Double? = if let ch = postChg, price > 0 { (ch / price) * 100 } else { nil }

            let quote = StockQuote(
                symbol: q.symbol,
                name: q.longName ?? q.shortName ?? q.symbol,
                price: price,
                change: change,
                changePercent: changePercent,
                currency: q.currency ?? "USD",
                marketState: marketState,
                dayHigh: q.regularMarketDayHigh,
                dayLow: q.regularMarketDayLow,
                fiftyTwoWeekHigh: q.fiftyTwoWeekHigh,
                fiftyTwoWeekLow: q.fiftyTwoWeekLow,
                preMarketPrice: q.preMarketPrice,
                preMarketChange: preChg,
                preMarketChangePercent: prePct,
                postMarketPrice: q.postMarketPrice,
                postMarketChange: postChg,
                postMarketChangePercent: postPct
            )

            quotes.append(quote)
            if let t = q.quoteType { types[q.symbol] = t }
        }

        return V7ParseResult(quotes: quotes, types: types)
    }

    private func fetchSingleQuote(symbol: String) async {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol

        // Two requests: daily for reliable price, intraday for extended hours
        guard let dailyUrl = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=2d"),
              let intraUrl = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1m&range=5d&includePrePost=true") else { return }

        do {
            // Fetch both in parallel
            async let dailyFetch = session.data(from: dailyUrl)
            async let intraFetch = session.data(from: intraUrl)

            let (dailyData, _) = try await dailyFetch
            let dailyResponse = try JSONDecoder().decode(YahooChartResponse.self, from: dailyData)
            guard let dailyResult = dailyResponse.chart.result?.first else { return }
            let meta = dailyResult.meta

            let price = meta.regularMarketPrice
            let previousClose = meta.chartPreviousClose ?? price
            let change = price - previousClose
            let changePercent = previousClose > 0 ? (change / previousClose) * 100 : 0

            // Determine market state from current trading period
            let now = Date().timeIntervalSince1970
            let ctp = meta.currentTradingPeriod
            let regEnd = ctp?.regular?.end ?? 0
            let regStart = ctp?.regular?.start ?? 0
            let preStart = ctp?.pre?.start ?? 0
            let postEnd = ctp?.post?.end ?? 0

            let marketState: String
            if now >= Double(regStart) && now < Double(regEnd) {
                marketState = "REGULAR"
            } else if now >= Double(preStart) && now < Double(regStart) {
                marketState = "PRE"
            } else if now >= Double(regEnd) && now < Double(postEnd) {
                marketState = "POST"
            } else {
                marketState = "CLOSED"
            }

            // Extract extended hours from intraday data
            var preMarketPrice: Double? = nil
            var postMarketPrice: Double? = nil

            if let (intraData, _) = try? await intraFetch,
               let intraResponse = try? JSONDecoder().decode(YahooChartResponse.self, from: intraData),
               let intraResult = intraResponse.chart.result?.first {

                let timestamps = intraResult.timestamp ?? []
                let closes = intraResult.indicators?.quote?.first?.close ?? []

                // Use regularMarketTime as the boundary for the last regular session
                let regTime = meta.regularMarketTime ?? 0

                // Find post-market: data after regularMarketTime on the last trading day
                for i in stride(from: timestamps.count - 1, through: 0, by: -1) {
                    if timestamps[i] > regTime, i < closes.count, let c = closes[i] {
                        postMarketPrice = c
                        break
                    }
                }

                // For pre-market: find data before regStart of today (only when market is PRE)
                if marketState == "PRE" {
                    for i in stride(from: timestamps.count - 1, through: 0, by: -1) {
                        if timestamps[i] >= preStart && timestamps[i] < regStart, i < closes.count, let c = closes[i] {
                            preMarketPrice = c
                            break
                        }
                    }
                }
            }

            let preChg: Double? = if let pm = preMarketPrice { pm - price } else { nil }
            let prePct: Double? = if let ch = preChg, price > 0 { (ch / price) * 100 } else { nil }
            let postChg: Double? = if let pm = postMarketPrice { pm - price } else { nil }
            let postPct: Double? = if let ch = postChg, price > 0 { (ch / price) * 100 } else { nil }

            let quote = StockQuote(
                symbol: meta.symbol,
                name: meta.longName ?? meta.shortName ?? meta.symbol,
                price: price,
                change: change,
                changePercent: changePercent,
                currency: meta.currency ?? "USD",
                marketState: marketState,
                dayHigh: nil,
                dayLow: nil,
                fiftyTwoWeekHigh: meta.fiftyTwoWeekHigh,
                fiftyTwoWeekLow: meta.fiftyTwoWeekLow,
                preMarketPrice: preMarketPrice,
                preMarketChange: preChg,
                preMarketChangePercent: prePct,
                postMarketPrice: postMarketPrice,
                postMarketChange: postChg,
                postMarketChangePercent: postPct
            )

            quotes[meta.symbol] = quote
            if let t = meta.instrumentType { StorageService.shared.setType(t, for: meta.symbol) }
        } catch {
        }
    }

    func rate(from currency: String, for purchaseDate: Date? = nil) -> Double {
        let preferred = StorageService.shared.preferredCurrency
        if currency == preferred { return 1.0 }
        if let date = purchaseDate {
            let dayStart = Calendar.current.startOfDay(for: date)
            let ts = Int(dayStart.timeIntervalSince1970)
            let key = "\(currency)\(preferred):\(ts)"
            if let historical = historicalRates[key] { return historical }
        }
        return exchangeRates["\(currency)\(preferred)"] ?? 1.0
    }

    func priceRate(from currency: String) -> Double {
        priceDisplay(for: currency).rate
    }

    /// How to render a price quoted in `currency`: the multiplier, and the
    /// currency the result is actually in.
    ///
    /// #24: the rate and the symbol have to be decided together. While the FX
    /// pair is still loading (right after switching currency in Settings, when
    /// `exchangeRates` was just cleared, or when the fetch failed) there is no
    /// rate, and multiplying by a silent 1.0 printed the native figure under the
    /// target currency's symbol — a $190 stock reading "€190". Degrading to the
    /// stock's own currency keeps the number and the symbol in agreement; the
    /// display switches over on its own once the rate lands.
    func priceDisplay(for currency: String) -> (rate: Double, currency: String) {
        let target = StorageService.shared.stockPriceCurrency
        guard !target.isEmpty, target != currency else { return (1.0, currency) }
        guard let rate = exchangeRates["\(currency)\(target)"] else { return (1.0, currency) }
        return (rate, target)
    }

    /// #24: a currency switch clears `exchangeRates` and refetches, so a single
    /// dropped request left every converted figure stranded until the next poll
    /// minutes later. One retry covers the transient failure.
    private func fetchExchangeRate(from: String, to: String) async {
        let symbol = "\(from)\(to)=X"
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d") else { return }

        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            do {
                let (data, _) = try await session.data(from: url)
                let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
                if let result = response.chart.result?.first {
                    exchangeRates["\(from)\(to)"] = result.meta.regularMarketPrice
                    return
                }
            } catch {
            }
        }
    }

    private func fetchHistoricalExchangeRate(from: String, to: String, dateTimestamp: Int) async {
        let symbol = "\(from)\(to)=X"
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let period1 = dateTimestamp
        let period2 = dateTimestamp + 86400
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&period1=\(period1)&period2=\(period2)") else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = response.chart.result?.first,
                  let closes = result.indicators?.quote?.first?.close,
                  !closes.isEmpty
            else { return }
            let validCloses = closes.compactMap { $0 }
            guard let rate = validCloses.first else { return }
            historicalRates["\(from)\(to):\(dateTimestamp)"] = rate
        } catch {
        }
    }

    /// Loads (or refreshes after ~1h) one year of daily closes for the detail
    /// chart. Real Yahoo history — the portfolio value chart intentionally has no
    /// backfill, but a single symbol's price history is accurate data.
    func ensurePriceHistory(for symbol: String) async {
        if let at = priceHistoryFetchedAt[symbol],
           Date().timeIntervalSince(at) < 3600,
           priceHistory[symbol]?.isEmpty == false { return }
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        // range=2y keeps FULL daily resolution (Yahoo downsamples 1d+max to coarse
        // data, which starves the 7D/1M ranges). "All" uses the monthly series below.
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=2y") else { return }
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = response.chart.result?.first else { return }
            let points = PriceHistory.points(timestamps: result.timestamp ?? [],
                                             closes: result.indicators?.quote?.first?.close ?? [])
            guard !points.isEmpty else { return }
            priceHistory[symbol] = points
            priceHistoryFetchedAt[symbol] = Date()
        } catch {
            // Non-fatal: the detail view keeps its placeholder band.
        }
    }

    /// Monthly closes over the full available history, for the "All" range. Cached ~6h.
    func ensurePriceHistoryMax(for symbol: String) async {
        if let at = priceHistoryMaxAt[symbol],
           Date().timeIntervalSince(at) < 21600,
           priceHistoryMax[symbol]?.isEmpty == false { return }
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1mo&range=max") else { return }
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = response.chart.result?.first else { return }
            let points = PriceHistory.points(timestamps: result.timestamp ?? [],
                                             closes: result.indicators?.quote?.first?.close ?? [])
            guard !points.isEmpty else { return }
            priceHistoryMax[symbol] = points
            priceHistoryMaxAt[symbol] = Date()
        } catch {
        }
    }

    /// Loads (or refreshes after ~5min) one trading day of 5-minute closes for
    /// the "1D" chart range.
    func ensureIntraday(for symbol: String) async {
        if let at = intradayFetchedAt[symbol],
           Date().timeIntervalSince(at) < 300,
           intradayHistory[symbol]?.isEmpty == false { return }
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        // Two days, not one: `range=1d` is empty until today's session prints, so
        // before the open (and all weekend) the 24H chart had nothing to draw and
        // fell through to the "no history yet" placeholder. `lastSession` keeps
        // the most recent session that actually traded.
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=5m&range=2d") else { return }
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = response.chart.result?.first else { return }
            let points = PriceHistory.lastSession(
                PriceHistory.points(timestamps: result.timestamp ?? [],
                                    closes: result.indicators?.quote?.first?.close ?? []))
            guard !points.isEmpty else { return }
            intradayHistory[symbol] = points
            intradayFetchedAt[symbol] = Date()
        } catch {
        }
    }

    /// Hourly closes over ~7 days for the "7D" range. Cached ~15min.
    func ensureIntradayWeek(for symbol: String) async {
        if let at = intradayWeekAt[symbol],
           Date().timeIntervalSince(at) < 900,
           intradayWeek[symbol]?.isEmpty == false { return }
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=60m&range=7d") else { return }
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = response.chart.result?.first else { return }
            let points = PriceHistory.points(timestamps: result.timestamp ?? [],
                                             closes: result.indicators?.quote?.first?.close ?? [])
            guard !points.isEmpty else { return }
            intradayWeek[symbol] = points
            intradayWeekAt[symbol] = Date()
        } catch {
        }
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

    /// Ensures historical rate is loaded for a holding (e.g. when opening edit view)
    func ensureHistoricalRate(for holding: Holding) async {
        guard let purchaseDate = holding.purchaseDate,
              let quote = quotes[holding.symbol],
              quote.currency != StorageService.shared.preferredCurrency
        else { return }
        let dayStart = Calendar.current.startOfDay(for: purchaseDate)
        let ts = Int(dayStart.timeIntervalSince1970)
        let key = "\(quote.currency)\(StorageService.shared.preferredCurrency):\(ts)"
        guard historicalRates[key] == nil else { return }
        await fetchHistoricalExchangeRate(from: quote.currency, to: StorageService.shared.preferredCurrency, dateTimestamp: ts)
    }

    /// Update a quote from a WebSocket tick. Returns true if the quote was meaningful.
    func applyTick(_ ticker: Yaticker) -> Bool {
        let symbol = ticker.id
        guard !symbol.isEmpty, ticker.price > 0 else { return false }

        let existing = quotes[symbol]

        let marketState: String
        switch ticker.marketHours {
        case .preMarket: marketState = "PRE"
        case .postMarket, .extendedHoursMarket: marketState = "POST"
        case .regularMarket: marketState = "REGULAR"
        default: marketState = existing?.marketState ?? "CLOSED"
        }

        let tickPrice = Double(ticker.price)
        let tickChange = Double(ticker.change)
        let tickChangePercent = Double(ticker.changePercent)

        // Only a REGULAR-session tick updates the regular price. A PRE/POST tick
        // must not overwrite it — otherwise a user with extended hours off would
        // see the pre/post price where they expect the last regular close. The
        // extended value is routed into the pre/post fields below instead.
        let isRegular = (marketState == "REGULAR")
        let price = isRegular ? tickPrice : (existing?.price ?? tickPrice)
        let change = isRegular ? tickChange : (existing?.change ?? tickChange)
        let changePercent = isRegular ? tickChangePercent : (existing?.changePercent ?? tickChangePercent)

        // Keep extended hours data from existing quote if WSS doesn't provide it
        let quote = StockQuote(
            symbol: symbol,
            name: existing?.name ?? ticker.shortName,
            price: price,
            change: change,
            changePercent: changePercent,
            currency: ticker.currency.isEmpty ? (existing?.currency ?? "USD") : ticker.currency,
            marketState: marketState,
            dayHigh: existing?.dayHigh,
            dayLow: existing?.dayLow,
            fiftyTwoWeekHigh: existing?.fiftyTwoWeekHigh,
            fiftyTwoWeekLow: existing?.fiftyTwoWeekLow,
            preMarketPrice: marketState == "PRE" ? tickPrice : existing?.preMarketPrice,
            preMarketChange: marketState == "PRE" ? tickChange : existing?.preMarketChange,
            preMarketChangePercent: marketState == "PRE" ? tickChangePercent : existing?.preMarketChangePercent,
            postMarketPrice: marketState == "POST" ? tickPrice : existing?.postMarketPrice,
            postMarketChange: marketState == "POST" ? tickChange : existing?.postMarketChange,
            postMarketChangePercent: marketState == "POST" ? tickChangePercent : existing?.postMarketChangePercent
        )

        quotes[symbol] = quote
        return true
    }

    func search(query: String) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://query2.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=10&newsCount=0") else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
            return response.quotes
        } catch {
            return []
        }
    }

    // MARK: - Finance News (Home tab)

    /// Refresh the Home news feed. Pulls stories related to the user's tracked
    /// symbols (or general market news when nothing is tracked), from the same
    /// Yahoo search endpoint used for quote lookup — no API key required.
    /// Throttled to at most once every 5 minutes unless `force` is set.
    func refreshNews(storageService: StorageService, force: Bool = false) async {
        if !force, !news.isEmpty, let last = lastNewsFetch,
           Date().timeIntervalSince(last) < 300 {
            return
        }
        isLoadingNews = true
        defer { isLoadingNews = false }

        let symbols = Self.collectSymbols(storageService: storageService).sorted()
        // Each query is (search term, reference ticker). For tracked symbols the
        // reference ticker is the symbol itself; the general-market fallback has none.
        let queries: [(term: String, symbol: String?)] = symbols.isEmpty
            ? [("stock market", nil)]
            : symbols.prefix(6).map { ($0, $0) }

        var seen = Set<String>()
        var collected: [NewsArticle] = []
        await withTaskGroup(of: [NewsArticle].self) { group in
            for query in queries {
                group.addTask { [weak self] in
                    await self?.fetchNewsChunk(query: query.term, sourceSymbol: query.symbol) ?? []
                }
            }
            for await chunk in group {
                for article in chunk where !article.link.isEmpty && seen.insert(article.id).inserted {
                    collected.append(article)
                }
            }
        }
        collected.sort { $0.publishTime > $1.publishTime }
        news = Array(collected.prefix(40))
        lastNewsFetch = Date()
    }

    private func fetchNewsChunk(query: String, sourceSymbol: String?) async -> [NewsArticle] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=0&newsCount=10") else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            let articles = try JSONDecoder().decode(YahooNewsResponse.self, from: data).news ?? []
            guard let sourceSymbol else { return articles }
            return articles.map { var a = $0; a.sourceSymbol = sourceSymbol; return a }
        } catch {
            return []
        }
    }
}

// MARK: - Yahoo Finance v8 Chart API Models

/// Yahoo `v8/finance/spark` — many symbols' close arrays in one response. Reuses
/// the chart response's `ChartResult` shape for each symbol's `response`.
private struct YahooSparkResponse: Codable {
    let spark: Spark
    struct Spark: Codable {
        let result: [SparkEntry]?
    }
    struct SparkEntry: Codable {
        let symbol: String
        let response: [YahooChartResponse.ChartResult]
    }
}

private struct YahooChartResponse: Codable {
    let chart: ChartData

    struct ChartData: Codable {
        let result: [ChartResult]?
        let error: ChartError?
    }

    struct ChartResult: Codable {
        let meta: ChartMeta
        let timestamp: [Int]?
        let indicators: Indicators?
    }

    struct Indicators: Codable {
        let quote: [QuoteData]?
    }

    struct QuoteData: Codable {
        let close: [Double?]?
    }

    struct ChartMeta: Codable {
        let symbol: String
        let currency: String?
        let regularMarketPrice: Double
        let regularMarketTime: Int?
        let chartPreviousClose: Double?
        let fiftyTwoWeekHigh: Double?
        let fiftyTwoWeekLow: Double?
        let longName: String?
        let shortName: String?
        let instrumentType: String?
        let currentTradingPeriod: TradingPeriods?
    }

    struct TradingPeriods: Codable {
        let pre: PeriodInfo?
        let regular: PeriodInfo?
        let post: PeriodInfo?
    }

    struct PeriodInfo: Codable {
        let start: Int
        let end: Int
    }

    struct ChartError: Codable {
        let code: String?
        let description: String?
    }
}

// MARK: - Yahoo Finance v7 Quote API Models

private struct YahooV7Response: Codable {
    let quoteResponse: QuoteResponse

    struct QuoteResponse: Codable {
        let result: [V7Quote]?
        let error: V7Error?
    }

    struct V7Quote: Codable {
        let symbol: String
        let longName: String?
        let shortName: String?
        let currency: String?
        let regularMarketPrice: Double?
        let regularMarketChange: Double?
        let regularMarketChangePercent: Double?
        let regularMarketPreviousClose: Double?
        let marketState: String?
        let regularMarketDayHigh: Double?
        let regularMarketDayLow: Double?
        let fiftyTwoWeekHigh: Double?
        let fiftyTwoWeekLow: Double?
        let preMarketPrice: Double?
        let postMarketPrice: Double?
        let quoteType: String?
    }

    struct V7Error: Codable {
        let code: String?
        let description: String?
    }
}

private struct YahooSearchResponse: Codable {
    let quotes: [SearchResult]
}

private struct YahooNewsResponse: Decodable {
    let news: [NewsArticle]?
}
