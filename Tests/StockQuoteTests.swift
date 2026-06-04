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
