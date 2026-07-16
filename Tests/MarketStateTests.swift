import XCTest
@testable import StockDock

/// Locks in the market-state / extended-hours logic on StockQuote — the fields
/// the desktop watchlist's "After hrs" column and several other views rely on
/// (effectivePrice, isExtendedHours, extendedChange, extendedChangePercent,
/// marketStateLabel). Previously only fiftyTwoWeekPosition was covered.
final class MarketStateTests: XCTestCase {

    private func quote(state: String,
                       price: Double = 100,
                       pre: Double? = nil, preChg: Double? = nil, prePct: Double? = nil,
                       post: Double? = nil, postChg: Double? = nil, postPct: Double? = nil) -> StockQuote {
        StockQuote(symbol: "X", name: "X", price: price, change: 0, changePercent: 0,
                   currency: "USD", marketState: state, dayHigh: nil, dayLow: nil,
                   fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil,
                   preMarketPrice: pre, preMarketChange: preChg, preMarketChangePercent: prePct,
                   postMarketPrice: post, postMarketChange: postChg, postMarketChangePercent: postPct)
    }

    // MARK: effectivePrice

    func testEffectivePricePreUsesPreMarket() {
        XCTAssertEqual(quote(state: "PRE", pre: 105).effectivePrice, 105)
    }

    func testEffectivePricePreFallsBackToRegular() {
        XCTAssertEqual(quote(state: "PRE").effectivePrice, 100)
    }

    func testEffectivePricePostUsesPostMarket() {
        XCTAssertEqual(quote(state: "POST", post: 96).effectivePrice, 96)
    }

    func testEffectivePriceClosedUsesPostMarket() {
        XCTAssertEqual(quote(state: "CLOSED", post: 96).effectivePrice, 96)
    }

    func testEffectivePriceClosedFallsBackToRegular() {
        XCTAssertEqual(quote(state: "CLOSED").effectivePrice, 100)
    }

    func testEffectivePriceRegularIsRegular() {
        XCTAssertEqual(quote(state: "REGULAR", pre: 105, post: 96).effectivePrice, 100)
    }

    // MARK: isExtendedHours

    func testIsExtendedHours() {
        XCTAssertTrue(quote(state: "PRE", pre: 105).isExtendedHours)
        XCTAssertFalse(quote(state: "PRE").isExtendedHours)
        XCTAssertTrue(quote(state: "POST", post: 96).isExtendedHours)
        XCTAssertFalse(quote(state: "POST").isExtendedHours)
        XCTAssertTrue(quote(state: "CLOSED", post: 96).isExtendedHours)
        XCTAssertFalse(quote(state: "CLOSED").isExtendedHours)
        XCTAssertFalse(quote(state: "REGULAR", pre: 105, post: 96).isExtendedHours)
    }

    // MARK: extendedChange / extendedChangePercent

    func testExtendedChangePre() {
        let q = quote(state: "PRE", pre: 105, preChg: 5, prePct: 5)
        XCTAssertEqual(q.extendedChange, 5)
        XCTAssertEqual(q.extendedChangePercent, 5)
    }

    func testExtendedChangePostAndClosedUsePostFields() {
        let post = quote(state: "POST", post: 96, postChg: -4, postPct: -4)
        XCTAssertEqual(post.extendedChange, -4)
        XCTAssertEqual(post.extendedChangePercent, -4)
        // CLOSED intentionally maps to the post-market fields, same as POST.
        let closed = quote(state: "CLOSED", post: 96, postChg: -4, postPct: -4)
        XCTAssertEqual(closed.extendedChange, -4)
        XCTAssertEqual(closed.extendedChangePercent, -4)
    }

    func testExtendedChangeRegularIsNil() {
        let q = quote(state: "REGULAR", preChg: 5, postChg: -4)
        XCTAssertNil(q.extendedChange)
        XCTAssertNil(q.extendedChangePercent)
    }

    // MARK: marketStateLabel

    func testMarketStateLabel() {
        XCTAssertEqual(quote(state: "PRE").marketStateLabel, "Pre")
        XCTAssertEqual(quote(state: "POST").marketStateLabel, "Post")
        // CLOSED shows "Post" only while post-market data is present.
        XCTAssertEqual(quote(state: "CLOSED", post: 96).marketStateLabel, "Post")
        XCTAssertEqual(quote(state: "CLOSED").marketStateLabel, "Closed")
        // REGULAR is an empty label (no badge), not "Regular".
        XCTAssertEqual(quote(state: "REGULAR").marketStateLabel, "")
        XCTAssertEqual(quote(state: "WEIRD").marketStateLabel, "Closed")
    }
}
