import XCTest
@testable import StockDock

/// Regression: in pre/post-market the "After hrs" column header must sort by the
/// extended-hours % move, not by the raw extended-hours price (a $500 stock up
/// 0.1% must NOT outrank a $10 stock up 5%). Rows without extended-hours data
/// always sink to the bottom regardless of direction.
final class ExtendedHoursSortTests: XCTestCase {

    private struct Row { let sym: String; let extPct: Double?; let extPrice: Double }

    private let rows = [
        Row(sym: "BIGPRICE", extPct: 0.1, extPrice: 500),  // huge price, tiny move
        Row(sym: "MOVER",    extPct: 5.0, extPrice: 10),    // small price, big move
        Row(sym: "DOWN",     extPct: -3.0, extPrice: 42),
        Row(sym: "NOEXT",    extPct: nil, extPrice: 0),     // no extended-hours quote
    ]

    func testSortsByPercentDescendingNotPrice() {
        let sorted = StorageService.sortedByExtendedPercent(rows, ascending: false) { $0.extPct }
        XCTAssertEqual(sorted.map(\.sym), ["MOVER", "BIGPRICE", "DOWN", "NOEXT"])
    }

    func testSortsByPercentAscending() {
        let sorted = StorageService.sortedByExtendedPercent(rows, ascending: true) { $0.extPct }
        // Ascending by %, but the nil row still sinks to the bottom.
        XCTAssertEqual(sorted.map(\.sym), ["DOWN", "BIGPRICE", "MOVER", "NOEXT"])
    }

    func testRowsWithoutExtendedDataAlwaysLast() {
        let sorted = StorageService.sortedByExtendedPercent(rows, ascending: false) { $0.extPct }
        XCTAssertEqual(sorted.last?.sym, "NOEXT")
    }
}
