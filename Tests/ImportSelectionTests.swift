import XCTest
@testable import StockDock

/// Import lets the user pick which portfolios from the file to bring in, and
/// whether to keep or replace the ones already in the app. "Delete all" wipes
/// every portfolio together with its notifications and history.
@MainActor
final class ImportSelectionTests: XCTestCase {

    private var saved: [Portfolio] = []

    override func setUp() async throws {
        saved = StorageService.shared.portfolios
    }

    override func tearDown() async throws {
        StorageService.shared.portfolios = saved
    }

    func testKeepExistingAppendsOnlyTheSelected() {
        let s = StorageService.shared
        s.portfolios = [Portfolio(name: "Old")]
        let a = Portfolio(name: "A"), b = Portfolio(name: "B")

        s.applyImport([a, b], selected: [b.id], replaceExisting: false)

        XCTAssertEqual(s.portfolios.map(\.name), ["Old", "B"])
    }

    func testReplaceExistingDropsTheOldOnes() {
        let s = StorageService.shared
        let old = Portfolio(name: "Old")
        s.portfolios = [old]
        s.addPortfolioNotification(PortfolioNotification(mode: .dailyPercent, threshold: 5), to: old.id)
        let a = Portfolio(name: "A")

        s.applyImport([a], selected: [a.id], replaceExisting: true)

        XCTAssertEqual(s.portfolios.map(\.name), ["A"])
        XCTAssertTrue(s.notifications(for: old.id).isEmpty)
    }

    func testReplaceKeepsTheOriginalNameWithoutSuffix() {
        let s = StorageService.shared
        s.portfolios = [Portfolio(name: "Growth")]
        let g = Portfolio(name: "Growth")

        s.applyImport([g], selected: [g.id], replaceExisting: true)

        XCTAssertEqual(s.portfolios.map(\.name), ["Growth"])
    }

    func testNothingSelectedChangesNothing() {
        let s = StorageService.shared
        s.portfolios = [Portfolio(name: "Old")]
        let a = Portfolio(name: "A")

        s.applyImport([a], selected: [], replaceExisting: true)

        XCTAssertEqual(s.portfolios.map(\.name), ["Old"])
    }

    func testDeleteAllPortfolios() {
        let s = StorageService.shared
        let p = Portfolio(name: "P")
        s.portfolios = [p, Portfolio(name: "Q")]
        s.addPortfolioNotification(PortfolioNotification(mode: .dailyPercent, threshold: 5), to: p.id)

        s.deleteAllPortfolios()

        XCTAssertTrue(s.portfolios.isEmpty)
        XCTAssertTrue(s.notifications(for: p.id).isEmpty)
    }
}
