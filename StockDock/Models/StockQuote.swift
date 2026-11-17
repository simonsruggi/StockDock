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

    /// Time of the last regular-session trade and the exchange's time zone
    /// (Yahoo `regularMarketTime` / `exchangeTimezoneName`). They date the
    /// session `change` belongs to, which can differ from the local calendar day
    /// (overnight, weekends, a user far from the exchange).
    var regularMarketTime: Date? = nil
    var exchangeTimeZone: String? = nil

    var id: String { symbol }

    /// Whether a lot bought at `purchase` missed the start of the move
    /// `effectiveChange(extendedHours:)` measures, i.e. never sat at the close
    /// that move starts from. In pre-market with an extended move, the move
    /// starts at the last regular close; otherwise it covers the quote's whole
    /// session day.
    func boughtWithinChange(_ purchase: Date, extendedHours: Bool, now: Date = Date(),
                            local: Calendar = .localGregorian) -> Bool {
        let preOnly = marketState == "PRE" && extendedHours && isExtendedHours && extendedChange != nil
        return Self.boughtWithinChange(purchase, sessionTime: regularMarketTime, zone: exchangeTimeZone,
                                       fromLastClose: preOnly, now: now, local: local)
    }

    /// - `sessionTime`: last regular trade (Yahoo `regularMarketTime`); it dates
    ///   the session, which can differ from the local day (overnight, weekends,
    ///   a user far from the exchange). Without it, "today" is the local day.
    /// - A purchase at exactly local midnight is a date picked in a calendar,
    ///   not a time: it is compared by day, the local day against the
    ///   exchange's session day. A real timestamp is compared exactly. A real
    ///   purchase at exactly local midnight is read as a picked date; east of
    ///   the exchange that can put it in the wrong session.
    /// Known gap: a lot bought after a close is counted from that close again
    /// once the next session starts (the previous close's time isn't known), so
    /// the after-hours move before the purchase shows in the next day's change.
    static func boughtWithinChange(_ purchase: Date, sessionTime: Date?, zone: String?, fromLastClose: Bool,
                                   now: Date, local: Calendar = .localGregorian) -> Bool {
        guard let sessionTime else { return local.isDate(purchase, inSameDayAs: now) }
        var exchange = Calendar(identifier: .gregorian)
        if let zone, let tz = TimeZone(identifier: zone) { exchange.timeZone = tz }
        if local.startOfDay(for: purchase) == purchase {
            let bought = dayNumber(local, purchase), session = dayNumber(exchange, sessionTime)
            return fromLastClose ? bought > session : bought >= session
        }
        return purchase >= (fromLastClose ? sessionTime : exchange.startOfDay(for: sessionTime))
    }

    /// Both day numbers must come from the same calendar system.
    private static func dayNumber(_ calendar: Calendar, _ date: Date) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

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
        // In pre-market `change` is the previous session's move: today's move is
        // the pre-market one alone, measured from that session's close.
        return marketState == "PRE" ? ext : change + ext
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

extension Calendar {
    /// Gregorian in the user's time zone, so local day numbers compare with the
    /// exchange's (a Buddhist or Japanese system calendar numbers years differently).
    static var localGregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }
}
