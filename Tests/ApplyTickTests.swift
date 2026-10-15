import XCTest
@testable import StockDock

/// Reproduces the field-reuse bug in `StockService.applyTick`: a PRE/POST-market
/// WebSocket tick was overwriting the *regular*-session price, so a user with
/// extended hours turned off saw the moving pre/post price where they expected
/// the last regular close.
@MainActor
final class ApplyTickTests: XCTestCase {

    private func makeTicker(id: String, price: Float, marketHours: MarketHoursType) -> Yaticker {
        var t = Yaticker()
        t.id = id
        t.price = price
        t.marketHours = marketHours
        t.currency = "USD"
        return t
    }

    override func tearDown() {
        StockService.shared.quotes.removeValue(forKey: "TSTX")
        super.tearDown()
    }

    /// A PRE-market tick must not clobber the regular price; it only updates the
    /// pre-market fields.
    func testPreMarketTickDoesNotClobberRegularPrice() {
        StockService.shared.quotes["TSTX"] = StockQuote(
            symbol: "TSTX", name: "Test", price: 100, change: 1, changePercent: 1,
            currency: "USD", marketState: "REGULAR", dayHigh: nil, dayLow: nil,
            fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil,
            preMarketPrice: nil, preMarketChange: nil, preMarketChangePercent: nil,
            postMarketPrice: nil, postMarketChange: nil, postMarketChangePercent: nil)

        _ = StockService.shared.applyTick(makeTicker(id: "TSTX", price: 105, marketHours: .preMarket))

        let q = StockService.shared.quotes["TSTX"]!
        XCTAssertEqual(q.price, 100, "regular price must be preserved during pre-market")
        XCTAssertEqual(q.preMarketPrice, 105, "pre-market price should reflect the tick")
        XCTAssertEqual(q.displayPrice(extendedHours: false), 100, "extended-off shows last regular close")
        XCTAssertEqual(q.displayPrice(extendedHours: true), 105, "extended-on shows live pre-market")
    }

    /// A POST-market tick behaves the same for the regular price.
    func testPostMarketTickDoesNotClobberRegularPrice() {
        StockService.shared.quotes["TSTX"] = StockQuote(
            symbol: "TSTX", name: "Test", price: 100, change: 1, changePercent: 1,
            currency: "USD", marketState: "REGULAR", dayHigh: nil, dayLow: nil,
            fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil,
            preMarketPrice: nil, preMarketChange: nil, preMarketChangePercent: nil,
            postMarketPrice: nil, postMarketChange: nil, postMarketChangePercent: nil)

        _ = StockService.shared.applyTick(makeTicker(id: "TSTX", price: 98, marketHours: .postMarket))

        let q = StockService.shared.quotes["TSTX"]!
        XCTAssertEqual(q.price, 100)
        XCTAssertEqual(q.postMarketPrice, 98)
        XCTAssertEqual(q.displayPrice(extendedHours: false), 100)
    }

    /// Yahoo replays the previous close as a REGULAR_MARKET tick during pre-market.
    /// It may refresh the regular price but must not switch the session off PRE.
    func testReplayedCloseTickKeepsPreMarketSession() {
        StockService.shared.quotes["TSTX"] = StockQuote(
            symbol: "TSTX", name: "Test", price: 100, change: 1, changePercent: 1,
            currency: "USD", marketState: "PRE", dayHigh: nil, dayLow: nil,
            fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil,
            preMarketPrice: 95, preMarketChange: -5, preMarketChangePercent: -5,
            postMarketPrice: nil, postMarketChange: nil, postMarketChangePercent: nil)

        var t = makeTicker(id: "TSTX", price: 100, marketHours: .regularMarket)
        t.time = Int64(Date().addingTimeInterval(-14 * 3600).timeIntervalSince1970 * 1000)
        _ = StockService.shared.applyTick(t)

        let q = StockService.shared.quotes["TSTX"]!
        XCTAssertEqual(q.marketState, "PRE")
        XCTAssertEqual(q.preMarketPrice, 95, "the replayed close must not land in the pre-market price")
        XCTAssertEqual(q.displayPrice(extendedHours: true), 95)
    }

    /// REGULAR exists only between open and close.
    func testClampToRegularSession() {
        let open = Date(timeIntervalSince1970: 1_792_071_000)   // 09:30 ET
        let close = Date(timeIntervalSince1970: 1_792_094_400)  // 16:00 ET
        let s = RegularSession(start: open, end: close, fetchedAt: open)
        XCTAssertEqual(StockService.clampToRegularSession("REGULAR", session: s, now: open.addingTimeInterval(-3600)), "PRE")
        XCTAssertEqual(StockService.clampToRegularSession("REGULAR", session: s, now: open.addingTimeInterval(60)), "REGULAR")
        XCTAssertEqual(StockService.clampToRegularSession("REGULAR", session: s, now: close.addingTimeInterval(60)), "POST")
        XCTAssertEqual(StockService.clampToRegularSession("PRE", session: s, now: open.addingTimeInterval(60)), "PRE")
        XCTAssertEqual(StockService.clampToRegularSession("REGULAR", session: nil, now: open), "REGULAR")
        // A window from another trading day is ignored.
        XCTAssertEqual(StockService.clampToRegularSession("REGULAR", session: s, now: open.addingTimeInterval(86_400)), "REGULAR")
    }

    /// A REGULAR tick updates the regular price as before.
    func testRegularTickUpdatesRegularPrice() {
        _ = StockService.shared.applyTick(makeTicker(id: "TSTX", price: 200, marketHours: .regularMarket))
        XCTAssertEqual(StockService.shared.quotes["TSTX"]?.price, 200)
    }
}
