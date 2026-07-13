import XCTest
@testable import StockDock

/// Regression tests for Yahoo v7 batch-quote parsing.
///
/// Bug: `V7Quote.regularMarketPrice` used to be non-optional, so a single
/// delisted/suspended ticker in the batch (which comes back without a price)
/// made the whole `JSONDecoder` call throw — dropping *every* symbol's live
/// quote and forcing a slow per-symbol fallback. Parsing must now skip the
/// bad entry and keep the good ones.
final class V7QuoteParsingTests: XCTestCase {

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    func testValidBatchParsesAllSymbols() throws {
        let data = json("""
        {"quoteResponse": {"result": [
          {"symbol": "AAPL", "regularMarketPrice": 200.0, "regularMarketPreviousClose": 190.0, "currency": "USD", "marketState": "REGULAR", "quoteType": "EQUITY"},
          {"symbol": "MSFT", "regularMarketPrice": 400.0, "currency": "USD", "marketState": "REGULAR"}
        ], "error": null}}
        """)
        let result = try StockService.parseV7Response(data)
        XCTAssertEqual(result.quotes.count, 2)
        XCTAssertEqual(Set(result.quotes.map { $0.symbol }), ["AAPL", "MSFT"])
        XCTAssertEqual(result.types["AAPL"], "EQUITY")
    }

    func testPartialQuoteWithoutPriceIsSkippedNotFatal() throws {
        // Middle entry has no regularMarketPrice — must not nuke the whole batch.
        let data = json("""
        {"quoteResponse": {"result": [
          {"symbol": "AAPL", "regularMarketPrice": 200.0, "currency": "USD", "marketState": "REGULAR"},
          {"symbol": "DEAD", "currency": "USD", "marketState": "CLOSED"},
          {"symbol": "MSFT", "regularMarketPrice": 400.0, "currency": "USD", "marketState": "REGULAR"}
        ], "error": null}}
        """)
        let result = try StockService.parseV7Response(data)
        XCTAssertEqual(result.quotes.count, 2, "the two priced symbols should still parse")
        XCTAssertEqual(Set(result.quotes.map { $0.symbol }), ["AAPL", "MSFT"])
        XCTAssertFalse(result.quotes.contains { $0.symbol == "DEAD" })
    }

    func testDerivedChangeAndPercent() throws {
        let data = json("""
        {"quoteResponse": {"result": [
          {"symbol": "AAPL", "regularMarketPrice": 110.0, "regularMarketPreviousClose": 100.0, "currency": "USD", "marketState": "REGULAR"}
        ], "error": null}}
        """)
        let q = try XCTUnwrap(try StockService.parseV7Response(data).quotes.first)
        XCTAssertEqual(q.change, 10.0, accuracy: 0.0001)
        XCTAssertEqual(q.changePercent, 10.0, accuracy: 0.0001)
    }

    func testEmptyResultYieldsNoQuotes() throws {
        let data = json(#"{"quoteResponse": {"result": [], "error": null}}"#)
        XCTAssertTrue(try StockService.parseV7Response(data).quotes.isEmpty)
    }
}
