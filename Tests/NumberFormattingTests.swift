import XCTest
@testable import StockDock

/// Covers issue #7 (2): thousands separator for numbers > 1,000 in the menu bar
/// and portfolios, with locale-aware grouping/decimal separators.
final class NumberFormattingTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US")
    private let itIT = Locale(identifier: "it_IT")
    private let deDE = Locale(identifier: "de_DE")

    // MARK: formatNumber

    func testGroupingAboveThousandEN() {
        XCTAssertEqual(StorageService.formatNumber(1234.56, decimals: 2, locale: enUS), "1,234.56")
        XCTAssertEqual(StorageService.formatNumber(1234567.8, decimals: 2, locale: enUS), "1,234,567.80")
    }

    func testGroupingAboveThousandIT() {
        XCTAssertEqual(StorageService.formatNumber(1234.56, decimals: 2, locale: itIT), "1.234,56")
    }

    func testGroupingAboveThousandDE() {
        XCTAssertEqual(StorageService.formatNumber(1234.56, decimals: 2, locale: deDE), "1.234,56")
    }

    func testNoGroupingBelowThousand() {
        XCTAssertEqual(StorageService.formatNumber(999.5, decimals: 2, locale: enUS), "999.50")
    }

    func testZeroDecimals() {
        XCTAssertEqual(StorageService.formatNumber(12345, decimals: 0, locale: enUS), "12,345")
    }

    func testNegativeKeepsGrouping() {
        XCTAssertEqual(StorageService.formatNumber(-4200.0, decimals: 2, locale: enUS), "-4,200.00")
    }

    // MARK: formatAmount (currency symbol before the figure, sign before symbol)

    func testAmountGroupedEN() {
        XCTAssertEqual(StorageService.formatAmount(1234.56, symbol: "€", locale: enUS), "€1,234.56")
    }

    func testAmountSignedPositive() {
        XCTAssertEqual(StorageService.formatAmount(820, symbol: "€", signed: true, locale: enUS), "+€820.00")
    }

    func testAmountSignedNegativeGrouped() {
        XCTAssertEqual(StorageService.formatAmount(-5400.5, symbol: "€", signed: true, locale: enUS), "-€5,400.50")
    }

    func testAmountUnsignedNegativeGrouped() {
        XCTAssertEqual(StorageService.formatAmount(-5400.5, symbol: "$", locale: enUS), "-$5,400.50")
    }

    func testAmountItalianGrouping() {
        XCTAssertEqual(StorageService.formatAmount(1234.56, symbol: "€", locale: itIT), "€1.234,56")
    }
}
