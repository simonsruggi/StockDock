import Foundation

extension StockService {
    /// Update a quote from a WebSocket tick. Returns true if the quote was meaningful.
    func applyTick(_ ticker: Yaticker) -> Bool {
        let symbol = ticker.id
        guard !symbol.isEmpty, ticker.price > 0 else { return false }

        let existing = quotes[symbol]

        let tickSession: String
        switch ticker.marketHours {
        case .preMarket: tickSession = "PRE"
        case .postMarket, .extendedHoursMarket: tickSession = "POST"
        case .regularMarket: tickSession = "REGULAR"
        default: tickSession = existing?.marketState ?? "CLOSED"
        }

        let tickPrice = Double(ticker.price)
        let tickChange = Double(ticker.change)
        let tickChangePercent = Double(ticker.changePercent)

        // Only a REGULAR-session tick updates the regular price. A PRE/POST tick
        // must not overwrite it — otherwise a user with extended hours off would
        // see the pre/post price where they expect the last regular close. The
        // extended value is routed into the pre/post fields below instead.
        let isRegular = (tickSession == "REGULAR")
        let price = isRegular ? tickPrice : (existing?.price ?? tickPrice)
        let change = isRegular ? tickChange : (existing?.change ?? tickChange)
        let changePercent = isRegular ? tickChangePercent : (existing?.changePercent ?? tickChangePercent)

        // During pre/post Yahoo re-sends the previous official close as a
        // REGULAR_MARKET tick stamped at the close time: a valid regular price,
        // but not a sign the session is open.
        let claimedState = (isRegular && Self.isStaleRegularTick(ticker)) ? (existing?.marketState ?? "CLOSED") : tickSession
        let marketState = clampedMarketState(claimedState, symbol: symbol)

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
            preMarketPrice: tickSession == "PRE" ? tickPrice : existing?.preMarketPrice,
            preMarketChange: tickSession == "PRE" ? tickChange : existing?.preMarketChange,
            preMarketChangePercent: tickSession == "PRE" ? tickChangePercent : existing?.preMarketChangePercent,
            postMarketPrice: tickSession == "POST" ? tickPrice : existing?.postMarketPrice,
            postMarketChange: tickSession == "POST" ? tickChange : existing?.postMarketChange,
            postMarketChangePercent: tickSession == "POST" ? tickChangePercent : existing?.postMarketChangePercent
        )

        quotes[symbol] = quote
        return true
    }

    /// A REGULAR_MARKET tick older than a few minutes is the replayed close,
    /// not live trading. Ticks without a timestamp are taken as live.
    nonisolated static func isStaleRegularTick(_ ticker: Yaticker, now: Date = Date()) -> Bool {
        guard ticker.time > 0 else { return false }
        let tickDate = Date(timeIntervalSince1970: Double(ticker.time) / 1000)
        return now.timeIntervalSince(tickDate) > 15 * 60
    }
}
