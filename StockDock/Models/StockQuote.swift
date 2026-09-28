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
