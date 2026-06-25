import XCTest
@testable import StockDock

/// Covers issue #8: index detection (no currency symbol for indices) and the
/// menu bar ticker ordering (as added / by type / alphabetical).
final class TickerOrderingTests: XCTestCase {

    // MARK: - isIndex (issue #8.3)

    func testIsIndexByType() {
        XCTAssertTrue(StorageService.isIndex(symbol: "^GSPC", type: "INDEX"))
        XCTAssertTrue(StorageService.isIndex(symbol: "GDAXI", type: "index")) // case-insensitive
    }

    func testIsIndexFalseForOtherTypes() {
        XCTAssertFalse(StorageService.isIndex(symbol: "AAPL", type: "EQUITY"))
        XCTAssertFalse(StorageService.isIndex(symbol: "VWCE.DE", type: "ETF"))
        XCTAssertFalse(StorageService.isIndex(symbol: "ES=F", type: "FUTURE"))
    }

    func testIsIndexFallsBackToCaretWhenTypeUnknown() {
        // No type yet (not in map): fall back to the "^" convention.
        XCTAssertTrue(StorageService.isIndex(symbol: "^IXIC", type: nil))
        XCTAssertTrue(StorageService.isIndex(symbol: "^FTSE", type: ""))
        XCTAssertFalse(StorageService.isIndex(symbol: "AAPL", type: nil))
    }

    func testTypeWinsOverCaretHeuristic() {
        // A non-index symbol that happens to start with "^" but is typed: trust the type.
        XCTAssertFalse(StorageService.isIndex(symbol: "^WEIRD", type: "EQUITY"))
    }

    // MARK: - tickerOrder (issue #8.1)

    private let types = [
        "AAPL": "EQUITY",
        "MSFT": "EQUITY",
        "VWCE.DE": "ETF",
        "^GSPC": "INDEX",
        "ES=F": "FUTURE",
    ]

    func testManualKeepsInsertionOrder() {
        let input = ["^GSPC", "AAPL", "ES=F", "VWCE.DE"]
        XCTAssertEqual(StorageService.tickerOrder(input, mode: "manual", types: types), input)
    }

    func testByTypeGroupsStocksEtfsIndicesFutures() {
        let input = ["^GSPC", "ES=F", "AAPL", "VWCE.DE", "MSFT"]
        // EQUITY (preserving AAPL before MSFT) → ETF → INDEX → FUTURE
        XCTAssertEqual(
            StorageService.tickerOrder(input, mode: "type", types: types),
            ["AAPL", "MSFT", "VWCE.DE", "^GSPC", "ES=F"]
        )
    }

    func testByTypeIsStableWithinGroup() {
        let input = ["MSFT", "AAPL"] // both EQUITY → keep relative order
        XCTAssertEqual(StorageService.tickerOrder(input, mode: "type", types: types), ["MSFT", "AAPL"])
    }

    func testByTypeUnknownGoesLast() {
        let input = ["TSLA", "AAPL"] // TSLA has no type → sorts after the typed equity
        XCTAssertEqual(StorageService.tickerOrder(input, mode: "type", types: types), ["AAPL", "TSLA"])
    }

    func testAlphabeticalOrder() {
        let input = ["MSFT", "aapl", "VWCE.DE"]
        XCTAssertEqual(
            StorageService.tickerOrder(input, mode: "alpha", types: types),
            ["aapl", "MSFT", "VWCE.DE"]
        )
    }

    func testUnknownModeFallsBackToManual() {
        let input = ["^GSPC", "AAPL"]
        XCTAssertEqual(StorageService.tickerOrder(input, mode: "bogus", types: types), input)
    }
}
