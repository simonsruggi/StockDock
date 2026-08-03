import Foundation

struct StockQuote: Identifiable, Codable {
    let symbol: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
    let currency: String
    let marketState: String

    // Extended hours
    let dayHigh: Double?
    let dayLow: Double?

    // 52-week range
    let fiftyTwoWeekHigh: Double?
    let fiftyTwoWeekLow: Double?

    let preMarketPrice: Double?
    let preMarketChange: Double?
    let preMarketChangePercent: Double?
    let postMarketPrice: Double?
    let postMarketChange: Double?
    let postMarketChangePercent: Double?

    var id: String { symbol }

    var isPositive: Bool { change >= 0 }

    /// Position of the current price within the 52-week range, 0 (low) … 1 (high).
    /// nil when range data is missing or degenerate (high == low).
    var fiftyTwoWeekPosition: Double? {
        guard let high = fiftyTwoWeekHigh, let low = fiftyTwoWeekLow, high > low else { return nil }
        let pos = (price - low) / (high - low)
        return min(max(pos, 0), 1)
    }

    /// Returns the most relevant current price based on market state
    var effectivePrice: Double {
        switch marketState {
        case "PRE":
            return preMarketPrice ?? price
        case "POST":
            return postMarketPrice ?? price
        case "CLOSED":
            // After hours closed: use post-market if available
            return postMarketPrice ?? price
        default:
            return price
        }
    }

    /// Price to evaluate alerts against. Returns nil during PRE/POST when the
    /// extended-hours price has not arrived yet, so alerts don't fire against the
    /// stale previous regular close. When the market is CLOSED, `price` is today's
    /// real close, so it's a valid fallback.
    var alertPrice: Double? {
        switch marketState {
        case "PRE":
            return preMarketPrice
        case "POST":
            return postMarketPrice
        case "CLOSED":
            return postMarketPrice ?? price
        default:
            return price
        }
    }

    /// True if we have extended hours data to show
    var isExtendedHours: Bool {
        switch marketState {
        case "PRE": return preMarketPrice != nil
        case "POST": return postMarketPrice != nil
        case "CLOSED": return postMarketPrice != nil
        default: return false
        }
    }

    /// Extended hours change (from regular close)
    var extendedChange: Double? {
        switch marketState {
        case "PRE": return preMarketChange
        case "POST", "CLOSED": return postMarketChange
        default: return nil
        }
    }

    /// Extended hours change percent
    var extendedChangePercent: Double? {
        switch marketState {
        case "PRE": return preMarketChangePercent
        case "POST", "CLOSED": return postMarketChangePercent
        default: return nil
        }
    }

    /// Price respecting the extended hours preference
    func displayPrice(extendedHours: Bool) -> Double {
        extendedHours ? effectivePrice : price
    }

    /// Day change per share CONSISTENT with `displayPrice(extendedHours:)` — i.e.
    /// from the previous regular close to the price actually shown. With extended
    /// hours on and pre/post data present it adds the extended move, so a
    /// portfolio valued at the extended price and its "today" figure agree
    /// (otherwise the value reflects the after-hours pop while "today" only sees
    /// the regular session, giving opposite signs).
    func effectiveChange(extendedHours: Bool) -> Double {
        guard extendedHours, isExtendedHours, let ext = extendedChange else { return change }
        return change + ext
    }

    var marketStateLabel: String {
        switch marketState {
        case "PRE": return "Pre"
        case "POST": return "Post"
        case "CLOSED":
            if postMarketPrice != nil { return "Post" }
            return "Closed"
        case "REGULAR": return ""
        default: return "Closed"
        }
    }
}

struct Portfolio: Identifiable, Codable {
    var id: UUID
    var name: String
    var holdings: [Holding]

    init(id: UUID = UUID(), name: String, holdings: [Holding] = []) {
        self.id = id
        self.name = name
        self.holdings = holdings
    }
}

struct Holding: Identifiable, Codable {
    var id: UUID
    var symbol: String
    /// Number of shares. Negative means a short position (gated behind the
    /// "Advanced" setting in the UI).
    var quantity: Double
    var avgPrice: Double
    /// Purchase date for historical exchange rate in cost basis calculation
    var purchaseDate: Date?
    /// Leverage multiplier applied to P&L and exposure (1.0 = unlevered).
    /// Optional so portfolios saved before 1.7.1 decode cleanly as unlevered.
    var leverage: Double?

    init(id: UUID = UUID(), symbol: String, quantity: Double, avgPrice: Double, purchaseDate: Date? = nil, leverage: Double? = nil) {
        self.id = id
        self.symbol = symbol
        self.quantity = quantity
        self.avgPrice = avgPrice
        self.purchaseDate = purchaseDate
        self.leverage = leverage
    }

    /// Leverage multiplier, defaulting to 1x when unset or invalid.
    var effectiveLeverage: Double {
        guard let l = leverage, l > 0 else { return 1 }
        return l
    }

    /// True for a short position (negative quantity).
    var isShort: Bool { quantity < 0 }

    /// Cost basis in the stock's own currency, signed and leverage-adjusted.
    /// Negative for shorts. Multiply by an FX rate for the preferred currency.
    var costBasisLocal: Double {
        avgPrice * quantity * effectiveLeverage
    }

    func pnl(currentPrice: Double) -> Double {
        (currentPrice - avgPrice) * quantity * effectiveLeverage
    }

    func dailyPnl(priceChange: Double) -> Double {
        priceChange * quantity * effectiveLeverage
    }

    func pnlPercent(currentPrice: Double) -> Double {
        guard avgPrice > 0 else { return 0 }
        // Exposure-relative return: a short gains when the price falls, so flip
        // the sign for negative quantities. Leverage scales P&L and exposure
        // equally, so it cancels out of the per-position percentage.
        let direction: Double = quantity < 0 ? -1 : 1
        return ((currentPrice - avgPrice) / avgPrice) * 100 * direction
    }

    func marketValue(currentPrice: Double) -> Double {
        currentPrice * quantity * effectiveLeverage
    }
}

struct SearchResult: Identifiable, Codable {
    let symbol: String
    let name: String
    let exchange: String
    let type: String

    var id: String { symbol }

    private enum CodingKeys: String, CodingKey {
        case symbol
        case name = "longname"
        case exchange
        case type = "quoteType"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        exchange = try container.decodeIfPresent(String.self, forKey: .exchange) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    }

    init(symbol: String, name: String, exchange: String, type: String) {
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.type = type
    }
}
