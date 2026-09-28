import Foundation

extension StockService {
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

            let pre = Self.extendedMove(q.preMarketPrice, from: price)
            let post = Self.extendedMove(q.postMarketPrice, from: price)

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
                preMarketChange: pre.change,
                preMarketChangePercent: pre.percent,
                postMarketPrice: q.postMarketPrice,
                postMarketChange: post.change,
                postMarketChangePercent: post.percent
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

            let pre = Self.extendedMove(preMarketPrice, from: price)
            let post = Self.extendedMove(postMarketPrice, from: price)

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
                preMarketChange: pre.change,
                preMarketChangePercent: pre.percent,
                postMarketPrice: postMarketPrice,
                postMarketChange: post.change,
                postMarketChangePercent: post.percent
            )

            quotes[meta.symbol] = quote
            if let t = meta.instrumentType { StorageService.shared.setType(t, for: meta.symbol) }
        } catch {
        }
    }

    /// Pre/post-market move of `extendedPrice` against the regular `price`:
    /// absolute change and percent, nil when there is no extended quote.
    nonisolated static func extendedMove(_ extendedPrice: Double?, from price: Double) -> (change: Double?, percent: Double?) {
        let change: Double? = if let pm = extendedPrice { pm - price } else { nil }
        let percent: Double? = if let ch = change, price > 0 { (ch / price) * 100 } else { nil }
        return (change, percent)
    }
}
