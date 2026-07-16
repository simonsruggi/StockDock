import XCTest
@testable import StockDock

/// Verifies the portfolio export → import round-trip that backs the window's
/// Import/Export feature. Uses the read-only `exportPortfolios`/`importPortfolios`
/// transforms (they don't mutate stored state), so this is safe to run.
@MainActor
final class ImportExportTests: XCTestCase {

    func testRoundTripPreservesData() throws {
        let s = StorageService.shared
        let p1 = Portfolio(name: "Growth", holdings: [
            Holding(symbol: "AAPL", quantity: 10, avgPrice: 178.5, purchaseDate: Date(timeIntervalSince1970: 1_700_000_000)),
            Holding(symbol: "MU", quantity: -5, avgPrice: 92, leverage: 2),
        ])
        let p2 = Portfolio(name: "Income", holdings: [Holding(symbol: "VWCE", quantity: 120, avgPrice: 108)])

        let data = try XCTUnwrap(s.exportPortfolios([p1, p2]))
        let imported = try XCTUnwrap(s.importPortfolios(from: data))

        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported.map(\.name), ["Growth", "Income"])

        let a = imported[0].holdings
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a[0].symbol, "AAPL")
        XCTAssertEqual(a[0].quantity, 10, accuracy: 1e-9)
        XCTAssertEqual(a[0].avgPrice, 178.5, accuracy: 1e-9)
        XCTAssertEqual(a[0].purchaseDate?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 1)
        // Short + leverage survive the round-trip.
        XCTAssertEqual(a[1].quantity, -5, accuracy: 1e-9)
        XCTAssertEqual(a[1].effectiveLeverage, 2, accuracy: 1e-9)
        XCTAssertTrue(a[1].isShort)
    }

    func testImportRejectsGarbage() {
        let s = StorageService.shared
        XCTAssertNil(s.importPortfolios(from: Data("not json".utf8)))
    }

    func testExportIsValidJSON() throws {
        let s = StorageService.shared
        let data = try XCTUnwrap(s.exportPortfolios([Portfolio(name: "X")]))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }
}
