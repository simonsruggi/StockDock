import XCTest
@testable import StockDock

/// Issue #10: forex and sub-dollar instruments need more than 2 decimals of
/// price precision (CADUSD=X was showing $0.71 instead of 0.7119).
final class PriceDecimalsTests: XCTestCase {

    func testForexSubDollarGetsFourDecimals() {
        // The exact case from the issue.
        XCTAssertEqual(StorageService.priceDecimals(symbol: "CADUSD=X", price: 0.7119), 4)
        XCTAssertEqual(StorageService.priceDecimals(symbol: "EURUSD=X", price: 1.0850), 4)
    }

    func testLargeForexCrossStaysTwoDecimals() {
        // USDJPY ≈ 149 — 4 decimals would just be trailing zeros.
        XCTAssertEqual(StorageService.priceDecimals(symbol: "USDJPY=X", price: 149.25), 2)
    }

    func testNormalStockGetsTwoDecimals() {
        XCTAssertEqual(StorageService.priceDecimals(symbol: "AAPL", price: 231.40), 2)
        XCTAssertEqual(StorageService.priceDecimals(symbol: "GLW", price: 174.41), 2)
    }

    func testSubDollarStockGetsFourDecimals() {
        // Penny stock / low-priced token under a dollar.
        XCTAssertEqual(StorageService.priceDecimals(symbol: "SNDL", price: 0.42), 4)
        XCTAssertEqual(StorageService.priceDecimals(symbol: "DOGE-USD", price: 0.1234), 4)
    }

    func testExactlyOneDollarStaysTwoDecimals() {
        XCTAssertEqual(StorageService.priceDecimals(symbol: "XYZ", price: 1.0), 2)
    }

    func testZeroPriceStaysTwoDecimals() {
        // Not-yet-loaded quotes have price 0 — don't switch to 4 decimals.
        XCTAssertEqual(StorageService.priceDecimals(symbol: "AAPL", price: 0), 2)
    }

    func testForexCaseInsensitiveSuffix() {
        XCTAssertEqual(StorageService.priceDecimals(symbol: "gbpusd=x", price: 1.26), 4)
    }
}
