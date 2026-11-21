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
    /// Weekly closes over 5 years, for the "5Y" chart range. Cached ~6h.
    @Published var priceHistory5y: [String: [PricePoint]] = [:]
    /// Intraday (5-minute) closes for the "24H" chart range. Cached ~5min.
    @Published var intradayHistory: [String: [PricePoint]] = [:]
    /// Hourly closes over ~7 days for the "7D" chart range. Cached ~15min.
    @Published var intradayWeek: [String: [PricePoint]] = [:]
    /// 5-minute closes including pre/post-market, for the portfolio "24H" range
    /// with extended hours on. Cached ~5min.
    @Published var intradayExtended: [String: [PricePoint]] = [:]
    /// Chart series whose last request failed ("kind:SYMBOL"), so the charts show
    /// "no history" instead of a spinner that never ends. Cleared on success.
    @Published var failedHistory: Set<String> = []

    let session: URLSession
    var crumb: String?
    var lastNewsFetch: Date?
    var priceHistoryFetchedAt: [String: Date] = [:]
    var priceHistoryMaxAt: [String: Date] = [:]
    var priceHistory5yAt: [String: Date] = [:]
    var intradayFetchedAt: [String: Date] = [:]
    var intradayWeekAt: [String: Date] = [:]
    var intradayExtendedAt: [String: Date] = [:]
    /// Daily closes of an FX pair ("USDEUR" → USDEUR=X) over 5 years, so the
    /// estimated value curve converts each day at that day's rate. Cached ~6h.
    @Published var fxHistory: [String: [PricePoint]] = [:]
    var fxHistoryAt: [String: Date] = [:]
    /// Watchlist Trend-column series per range and symbol (see `ensureSparklines`).
    @Published var sparkSeries: [SymbolChartRange: [String: [PricePoint]]] = [:]
    var sparkSeriesAt: [SymbolChartRange: Date] = [:]
    var regularSessions: [String: RegularSession] = [:]

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
        evictStaleHistory(keeping: allSymbols)

        await fetchQuotes(symbols: Array(allSymbols))
        await refreshExchangeRates(storageService: storageService)
    }
}
