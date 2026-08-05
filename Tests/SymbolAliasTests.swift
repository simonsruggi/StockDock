import XCTest
@testable import StockDock

/// Covers issue #12: per-symbol custom display names for tickers that read badly
/// in the menu bar ("CAD/USD", "^GSPC").
@MainActor
final class SymbolAliasTests: XCTestCase {

    private func makeStorage() -> StorageService {
        let s = StorageService.shared
        s.symbolAlias = [:]
        return s
    }

    func testAliasIsEmptyWhenUnset() {
        let s = makeStorage()
        XCTAssertEqual(s.alias(for: "AAPL"), "")
    }

    func testSetAndReadAlias() {
        let s = makeStorage()
        s.setAlias("CAD", for: "CAD/USD")
        XCTAssertEqual(s.alias(for: "CAD/USD"), "CAD")
    }

    func testAliasIsTrimmed() {
        let s = makeStorage()
        s.setAlias("  S&P  ", for: "^GSPC")
        XCTAssertEqual(s.alias(for: "^GSPC"), "S&P")
    }

    /// Saving a blank name clears the alias rather than storing "", so
    /// `displayLabel` has a single "no alias" path to fall back through.
    func testBlankAliasClearsTheEntry() {
        let s = makeStorage()
        s.setAlias("CAD", for: "CAD/USD")
        s.setAlias("   ", for: "CAD/USD")
        XCTAssertNil(s.symbolAlias["CAD/USD"])
        XCTAssertEqual(s.alias(for: "CAD/USD"), "")
    }

    func testDisplayLabelPrefersTheAlias() {
        let s = makeStorage()
        s.setAlias("S&P", for: "^GSPC")
        XCTAssertEqual(s.displayLabel(for: "^GSPC", fallback: "^GSPC"), "S&P")
        // The alias also wins over the company name (the #8.2 "show name" path).
        XCTAssertEqual(s.displayLabel(for: "^GSPC", fallback: "S&P 500 INDEX"), "S&P")
    }

    func testDisplayLabelFallsBackWhenUnset() {
        let s = makeStorage()
        XCTAssertEqual(s.displayLabel(for: "AAPL", fallback: "AAPL"), "AAPL")
        XCTAssertEqual(s.displayLabel(for: "AAPL", fallback: "Apple Inc."), "Apple Inc.")
    }

    func testAliasesAreIndependentPerSymbol() {
        let s = makeStorage()
        s.setAlias("CAD", for: "CAD/USD")
        s.setAlias("Gold", for: "GC=F")
        XCTAssertEqual(s.alias(for: "CAD/USD"), "CAD")
        XCTAssertEqual(s.alias(for: "GC=F"), "Gold")
        XCTAssertEqual(s.alias(for: "AAPL"), "")
    }
}
