import Foundation

extension StockService {
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
}
