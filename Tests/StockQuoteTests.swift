import XCTest
@testable import StockDock

final class StockQuoteTests: XCTestCase {

    private func quote(price: Double, high: Double?, low: Double?) -> StockQuote {
        StockQuote(symbol: "X", name: "X", price: price, change: 0, changePercent: 0,
                   currency: "USD", marketState: "REGULAR", dayHigh: nil, dayLow: nil,
                   fiftyTwoWeekHigh: high, fiftyTwoWeekLow: low,
                   preMarketPrice: nil, preMarketChange: nil, preMarketChangePercent: nil,
                   postMarketPrice: nil, postMarketChange: nil, postMarketChangePercent: nil)
    }

    func testPositionAtLowIsZero() {
        XCTAssertEqual(quote(price: 50, high: 150, low: 50).fiftyTwoWeekPosition, 0.0)
    }

    // MARK: - effectiveChange (extended-hours-aware day change)

    private func postMarketQuote(regularChange: Double, postChange: Double) -> StockQuote {
        // Regular session down `regularChange`, then post-market up `postChange`.
        StockQuote(symbol: "MU", name: "Micron", price: 100, change: regularChange, changePercent: 0,
                   currency: "USD", marketState: "POST", dayHigh: nil, dayLow: nil,
                   fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil,
                   preMarketPrice: nil, preMarketChange: nil, preMarketChangePercent: nil,
                   postMarketPrice: 100 + postChange, postMarketChange: postChange, postMarketChangePercent: nil)
    }

    /// Reproduces the reported bug: value uses the after-hours price (up) but the
    /// day change ignored it (down). With extended hours on, the change must
    /// include the post-market move so TODAY agrees in sign with the value.
    func testEffectiveChangeIncludesExtendedWhenEnabled() {
        let q = postMarketQuote(regularChange: -0.5, postChange: 5.0)   // -0.5 regular, +5 post
        XCTAssertEqual(q.effectiveChange(extendedHours: true), 4.5, accuracy: 1e-9)   // net UP
        XCTAssertEqual(q.effectiveChange(extendedHours: false), -0.5, accuracy: 1e-9) // regular only
    }

    /// In pre-market `change` is yesterday's move: today is the pre-market move only.
    func testEffectiveChangePreMarketExcludesPreviousSession() {
        let q = StockQuote(symbol: "MU", name: "Micron", price: 914.13, change: -38.9, changePercent: -4.08,
                           currency: "USD", marketState: "PRE", dayHigh: nil, dayLow: nil,
                           fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil,
                           preMarketPrice: 879, preMarketChange: -35.13, preMarketChangePercent: -3.84,
                           postMarketPrice: nil, postMarketChange: nil, postMarketChangePercent: nil)
        XCTAssertEqual(q.effectiveChange(extendedHours: true), -35.13, accuracy: 1e-9)
    }

    func testEffectiveChangeRegularSessionUnaffected() {
        let q = quote(price: 100, high: nil, low: nil)  // REGULAR, no extended
        XCTAssertEqual(q.effectiveChange(extendedHours: true), q.change, accuracy: 1e-9)
        XCTAssertEqual(q.effectiveChange(extendedHours: false), q.change, accuracy: 1e-9)
    }

    func testPositionAtHighIsOne() {
        XCTAssertEqual(quote(price: 150, high: 150, low: 50).fiftyTwoWeekPosition, 1.0)
    }

    func testPositionMidpoint() {
        XCTAssertEqual(quote(price: 100, high: 150, low: 50).fiftyTwoWeekPosition!, 0.5, accuracy: 0.0001)
    }

    func testPositionClampsBelowLow() {
        XCTAssertEqual(quote(price: 10, high: 150, low: 50).fiftyTwoWeekPosition, 0.0)
    }

    func testPositionClampsAboveHigh() {
        XCTAssertEqual(quote(price: 999, high: 150, low: 50).fiftyTwoWeekPosition, 1.0)
    }

    func testPositionNilWhenRangeMissing() {
        XCTAssertNil(quote(price: 100, high: nil, low: 50).fiftyTwoWeekPosition)
        XCTAssertNil(quote(price: 100, high: 150, low: nil).fiftyTwoWeekPosition)
    }

    func testPositionNilWhenDegenerate() {
        XCTAssertNil(quote(price: 100, high: 100, low: 100).fiftyTwoWeekPosition)
    }
}
