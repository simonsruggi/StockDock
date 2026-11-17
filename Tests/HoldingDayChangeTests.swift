import XCTest
@testable import StockDock

/// A lot bought within the move a quote's day change measures was never held
/// at the close that move starts from, so its day counts from the buy price.
@MainActor
final class HoldingDayChangeTests: XCTestCase {
    private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private func zone(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: id)!
        return c
    }

    private func quote(price: Double, change: Double, state: String = "CLOSED", session: Date?, zone: String?,
                       preMarketPrice: Double? = nil, preMarketChange: Double? = nil) -> StockQuote {
        StockQuote(symbol: "TSTDAY", name: "Test", price: price, change: change, changePercent: 0, currency: "EUR",
                   marketState: state, dayHigh: nil, dayLow: nil, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil,
                   preMarketPrice: preMarketPrice, preMarketChange: preMarketChange, preMarketChangePercent: nil,
                   postMarketPrice: nil, postMarketChange: nil, postMarketChangePercent: nil,
                   regularMarketTime: session, exchangeTimeZone: zone)
    }

    private func lot(_ date: Date?, avg: Double = 139.43) -> Holding {
        Holding(symbol: "TSTDAY", quantity: 10, avgPrice: avg, purchaseDate: date)
    }

    // MARK: Through the service entry point every view uses

    /// Fixed so the tests don't depend on the machine's zone.
    private let berlin: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    /// Bought Tuesday 20:00 Berlin after Xetra closed at 139.40 (prev close 145.34).
    /// The day counts from the buy price that evening and overnight, while the
    /// quote still carries Tuesday's session, and from the close once Wednesday trades.
    func testLotBoughtAfterCloseCountsFromBuyPriceUntilNextSession() {
        let q = quote(price: 139.40, change: -5.94, session: utc("2026-11-17T16:30:00Z"), zone: "Europe/Berlin")
        let h = lot(utc("2026-11-17T19:00:00Z"))
        let live = HyperliquidService.shared
        XCTAssertEqual(live.liveChange(for: q, holding: h, extendedHours: false, now: utc("2026-11-17T20:00:00Z"), local: berlin),
                       -0.03, accuracy: 1e-9)
        XCTAssertEqual(live.liveChange(for: q, holding: h, extendedHours: false, now: utc("2026-11-18T02:00:00Z"), local: berlin),
                       -0.03, accuracy: 1e-9, "overnight: still Tuesday's session")

        let wednesday = quote(price: 141.00, change: 1.60, session: utc("2026-11-18T09:00:00Z"), zone: "Europe/Berlin")
        XCTAssertEqual(live.liveChange(for: wednesday, holding: h, extendedHours: false, now: utc("2026-11-18T09:05:00Z"), local: berlin),
                       1.60, accuracy: 1e-9)
    }

    func testOlderAndUndatedLotsUseQuoteChange() {
        let q = quote(price: 139.40, change: -5.94, session: utc("2026-11-17T16:30:00Z"), zone: "Europe/Berlin")
        let now = utc("2026-11-17T20:00:00Z")
        XCTAssertEqual(HyperliquidService.shared.liveChange(for: q, holding: lot(utc("2026-11-12T10:00:00Z"), avg: 100),
                                                            extendedHours: false, now: now, local: berlin), -5.94)
        XCTAssertEqual(HyperliquidService.shared.liveChange(for: q, holding: lot(nil, avg: 100),
                                                            extendedHours: false, now: now, local: berlin), -5.94)
    }

    /// With extended hours on in pre-market, the move starts at the last close:
    /// a lot bought during the previous session is outside it.
    func testPreMarketExtendedMoveExcludesPreviousSessionLot() {
        let q = quote(price: 100, change: 4, state: "PRE", session: utc("2026-11-16T21:00:00Z"),
                      zone: "America/New_York", preMarketPrice: 101, preMarketChange: 1)
        let h = lot(utc("2026-11-16T14:37:00Z"), avg: 97)
        let now = utc("2026-11-17T12:00:00Z")
        XCTAssertEqual(HyperliquidService.shared.liveChange(for: q, holding: h, extendedHours: true, now: now, local: berlin), 1,
                       accuracy: 1e-9)
        // Extended hours off: the regular change covers Monday's session, which the lot joined.
        XCTAssertEqual(HyperliquidService.shared.liveChange(for: q, holding: h, extendedHours: false, now: now, local: berlin), 3,
                       accuracy: 1e-9)
    }

    // MARK: Day rules

    /// A date picked in the form is stored at local midnight. From Berlin, a US
    /// stock bought "Tuesday" falls before New York's Tuesday as an instant, but
    /// is Tuesday's lot.
    func testDatePickedLocallyMatchesExchangeSessionDay() {
        let berlin = zone("Europe/Berlin")
        let picked = berlin.startOfDay(for: utc("2026-11-17T12:00:00Z"))
        XCTAssertTrue(StockQuote.boughtWithinChange(picked, sessionTime: utc("2026-11-17T15:30:00Z"), zone: "America/New_York",
                                                    fromLastClose: false, now: utc("2026-11-17T16:00:00Z"), local: berlin))
        XCTAssertFalse(StockQuote.boughtWithinChange(picked, sessionTime: utc("2026-11-18T15:30:00Z"), zone: "America/New_York",
                                                     fromLastClose: false, now: utc("2026-11-18T16:00:00Z"), local: berlin))
    }

    /// Tokyo picks Tuesday for a buy in US pre-market (still Monday's session in
    /// New York): the local midnight lies before Monday's close, the day after it.
    func testDatePickedAheadOfExchangeCountsInPreMarket() {
        let tokyo = zone("Asia/Tokyo")
        let picked = tokyo.startOfDay(for: utc("2026-11-17T03:00:00Z"))
        XCTAssertTrue(StockQuote.boughtWithinChange(picked, sessionTime: utc("2026-11-16T21:00:00Z"), zone: "America/New_York",
                                                    fromLastClose: true, now: utc("2026-11-17T12:00:00Z"), local: tokyo))
    }

    /// A timestamped buy is compared exactly: Tokyo at 01:00 Tuesday is Monday's
    /// New York session, so Tuesday's session doesn't count it as new.
    func testTimestampedPurchaseUsesExchangeDay() {
        let tokyo = zone("Asia/Tokyo")
        let bought = utc("2026-11-16T16:00:00Z")              // Tue 01:00 Tokyo, Mon 11:00 NY
        XCTAssertTrue(StockQuote.boughtWithinChange(bought, sessionTime: utc("2026-11-16T17:00:00Z"), zone: "America/New_York",
                                                    fromLastClose: false, now: utc("2026-11-16T17:00:00Z"), local: tokyo))
        XCTAssertFalse(StockQuote.boughtWithinChange(bought, sessionTime: utc("2026-11-17T15:00:00Z"), zone: "America/New_York",
                                                     fromLastClose: false, now: utc("2026-11-17T15:00:00Z"), local: tokyo))
    }

    func testWithoutSessionFallsBackToLocalDay() {
        let berlin = zone("Europe/Berlin")
        XCTAssertTrue(StockQuote.boughtWithinChange(utc("2026-11-17T08:00:00Z"), sessionTime: nil, zone: nil,
                                                    fromLastClose: false, now: utc("2026-11-17T20:00:00Z"), local: berlin))
        XCTAssertFalse(StockQuote.boughtWithinChange(utc("2026-11-16T08:00:00Z"), sessionTime: nil, zone: nil,
                                                     fromLastClose: false, now: utc("2026-11-17T20:00:00Z"), local: berlin))
    }

    // MARK: Ticks carry the session date

    func testRegularTickAdvancesSessionEvenWhenStale() {
        var t = Yaticker()
        t.id = "TSTDAY"; t.price = 105; t.marketHours = .regularMarket
        t.time = Int64(utc("2026-11-17T14:30:00Z").timeIntervalSince1970 * 1000)
        let monday = utc("2026-11-16T21:00:00Z")
        XCTAssertEqual(StockService.sessionTime(after: t, isRegular: true, existing: monday), utc("2026-11-17T14:30:00Z"))
        // A replayed older close never moves it back; pre/post ticks don't touch it.
        XCTAssertEqual(StockService.sessionTime(after: t, isRegular: true, existing: utc("2026-11-17T21:00:00Z")),
                       utc("2026-11-17T21:00:00Z"))
        XCTAssertEqual(StockService.sessionTime(after: t, isRegular: false, existing: monday), monday)
    }
}
