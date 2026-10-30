import Foundation

/// Tools StockDock exposes over MCP. Quotes and exchange rates are fetched fresh from Yahoo
/// Finance on every call; portfolios and watchlist are read from the app's data and never saved.
enum StockDockTools {
    static func server() -> MCPServer {
        MCPServer(
            name: "stockdock",
            instructions: "Portfolios, P&L and watchlist from StockDock, plus live quotes for any Yahoo Finance ticker (stocks, ETFs, crypto like BTC-USD, forex like EURUSD=X). Values are in the user's preferred currency, prices in the stock's own currency. Read-only.",
            tools: [portfolio, watchlist, quote]
        )
    }

    private static let portfolio = MCPTool(
        name: "get_portfolio",
        description: "Holdings of the user's portfolios with live value, cost, total P&L and today's change, in the preferred currency. The combined total leaves out portfolios marked as excluded from the total.",
        inputSchema: [
            "type": "object",
            "properties": ["name": ["type": "string", "description": "Only the portfolio with this name (default: all)"]],
        ],
        handler: { args in
            let name = args.string("name")
            return try MCPServer.wait { try await portfolios(named: name) }
        }
    )

    private static let watchlist = MCPTool(
        name: "get_watchlist",
        description: "Live quotes of the symbols in the user's watchlist.",
        inputSchema: ["type": "object", "properties": [String: Any]()],
        handler: { _ in
            try MCPServer.wait {
                let symbols = StorageService.shared.watchlist
                guard !symbols.isEmpty else { throw MCPToolError("The watchlist is empty.") }
                return ["quotes": await quotes(for: symbols)]
            }
        }
    )

    private static let quote = MCPTool(
        name: "get_quote",
        description: "Live quote for one or more Yahoo Finance tickers, even ones not in the watchlist: price, today's change, day and 52-week range, market state and extended-hours price.",
        inputSchema: [
            "type": "object",
            "properties": ["symbols": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 20,
                                       "description": "Tickers such as AAPL, VWCE.DE, BTC-USD"]],
            "required": ["symbols"],
        ],
        handler: { args in
            let symbols = (args["symbols"] as? [String] ?? [])
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                .filter { !$0.isEmpty }
            guard !symbols.isEmpty else { throw MCPToolError("Pass at least one ticker in symbols.") }
            return try MCPServer.wait { ["quotes": await quotes(for: Array(symbols.prefix(20)))] }
        }
    )

    @MainActor
    private static func quotes(for symbols: [String]) async -> [[String: Any]] {
        let stocks = StockService.shared
        await stocks.fetchQuotes(symbols: symbols)
        let extended = StorageService.shared.showExtendedHours
        return symbols.map { symbol -> [String: Any] in
            guard let q = stocks.quotes[symbol] else { return ["symbol": symbol, "error": "No quote found"] }
            var row: [String: Any] = [
                "symbol": q.symbol,
                "name": q.name,
                "price": number(HyperliquidService.shared.livePrice(for: q, extendedHours: extended)),
                "regular_market_price": number(q.price),
                "change": number(q.change),
                "change_percent": number(q.changePercent),
                "currency": q.currency,
                "market_state": q.marketState,
            ]
            if let v = q.dayLow { row["day_low"] = number(v) }
            if let v = q.dayHigh { row["day_high"] = number(v) }
            if let v = q.fiftyTwoWeekLow { row["week52_low"] = number(v) }
            if let v = q.fiftyTwoWeekHigh { row["week52_high"] = number(v) }
            if let v = q.preMarketPrice { row["pre_market_price"] = number(v) }
            if let v = q.postMarketPrice { row["post_market_price"] = number(v) }
            return row
        }
    }

    @MainActor
    private static func portfolios(named name: String?) async throws -> [String: Any] {
        let storage = StorageService.shared
        let stocks = StockService.shared
        var selected = storage.portfolios
        if let name, !name.isEmpty {
            selected = selected.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            guard !selected.isEmpty else {
                throw MCPToolError("No portfolio named \(name). Portfolios: \(storage.portfolios.map(\.name).joined(separator: ", "))")
            }
        }
        guard selected.contains(where: { !$0.holdings.isEmpty }) else {
            throw MCPToolError("No holdings yet: add them in StockDock's Portfolio tab.")
        }

        await stocks.refreshAll(storageService: storage)
        for holding in selected.flatMap(\.holdings) {
            await stocks.ensureHistoricalRate(for: holding)
        }
        let extended = storage.showExtendedHours
        let live = HyperliquidService.shared

        var totalValue = 0.0, totalCost = 0.0, totalDay = 0.0
        let rows = selected.map { portfolio -> [String: Any] in
            var value = 0.0, cost = 0.0, day = 0.0
            var missing: [String] = []
            let holdings = portfolio.holdings.compactMap { h -> [String: Any]? in
                guard let q = stocks.quotes[h.symbol] else {
                    missing.append(h.symbol)
                    return nil
                }
                let price = live.livePrice(for: q, extendedHours: extended)
                let rate = stocks.rate(from: q.currency)
                let costRate = stocks.costRate(for: h, currency: q.currency)
                let hValue = h.marketValue(currentPrice: price) * rate
                let hCost = h.costBasisLocal * costRate
                let hDay = h.dailyPnl(priceChange: live.liveChange(for: q, extendedHours: extended)) * rate
                value += hValue; cost += hCost; day += hDay
                var row: [String: Any] = [
                    "symbol": h.symbol,
                    "name": q.name,
                    "quantity": number(h.quantity),
                    "average_price": number(h.avgPrice),
                    "price": number(price),
                    "price_currency": q.currency,
                    "value": number(hValue),
                    "pnl": number(hValue - hCost),
                    "pnl_percent": number(PortfolioValuation.pnlPercent(value: hValue, cost: hCost)),
                    "today": number(hDay),
                ]
                if h.effectiveLeverage != 1 { row["leverage"] = number(h.effectiveLeverage) }
                return row
            }
            if !portfolio.isExcludedFromTotal {
                totalValue += value; totalCost += cost; totalDay += day
            }
            var row: [String: Any] = [
                "name": portfolio.name,
                "value": number(value),
                "cost": number(cost),
                "pnl": number(value - cost),
                "pnl_percent": number(PortfolioValuation.pnlPercent(value: value, cost: cost)),
                "today": number(day),
                "holdings": holdings,
            ]
            if portfolio.isExcludedFromTotal { row["excluded_from_total"] = true }
            if !missing.isEmpty { row["holdings_without_quote"] = missing }
            return row
        }

        return [
            "currency": storage.preferredCurrency,
            "fetched_at": ISO8601DateFormatter().string(from: Date()),
            "total": [
                "value": number(totalValue),
                "cost": number(totalCost),
                "pnl": number(totalValue - totalCost),
                "pnl_percent": number(PortfolioValuation.pnlPercent(value: totalValue, cost: totalCost)),
                "today": number(totalDay),
            ],
            "portfolios": rows,
        ]
    }

    /// Up to 4 decimals (crypto and forex need them), as Decimal so JSON stays readable.
    private static func number(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.4f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)) ?? 0
    }
}
