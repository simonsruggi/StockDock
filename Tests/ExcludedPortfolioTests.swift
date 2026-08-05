import XCTest
@testable import StockDock

/// Covers issue #14.1: a portfolio can be kept out of the combined total (a
/// paper/"fantasy" portfolio) while staying a fully working portfolio of its own.
@MainActor
final class ExcludedPortfolioTests: XCTestCase {

    private func makeStorage(_ portfolios: [Portfolio]) -> StorageService {
        let s = StorageService.shared
        s.portfolios = portfolios
        return s
    }

    private func holding(_ symbol: String, qty: Double, avg: Double) -> Holding {
        Holding(symbol: symbol, quantity: qty, avgPrice: avg)
    }

    // MARK: - The model default

    /// Portfolios saved before this feature have no flag at all and must keep
    /// counting — the whole point of the optional.
    func testPortfoliosAreCountedByDefault() {
        let p = Portfolio(name: "Main")
        XCTAssertFalse(p.isExcludedFromTotal)
    }

    func testExplicitFalseAlsoCounts() {
        let p = Portfolio(name: "Main", holdings: [], excludedFromTotal: false)
        XCTAssertFalse(p.isExcludedFromTotal)
    }

    // MARK: - countedPortfolios

    func testCountedPortfoliosDropsTheExcludedOne() {
        let s = makeStorage([
            Portfolio(name: "Real"),
            Portfolio(name: "Fantasy", holdings: [], excludedFromTotal: true),
        ])
        XCTAssertEqual(s.countedPortfolios.map(\.name), ["Real"])
    }

    func testCountedPortfoliosKeepsEverythingWhenNothingIsExcluded() {
        let s = makeStorage([Portfolio(name: "A"), Portfolio(name: "B")])
        XCTAssertEqual(s.countedPortfolios.count, 2)
    }

    /// Excluding must not remove the portfolio itself — it still shows in the
    /// sidebar, keeps its holdings, its snapshots and its notifications.
    func testExcludingKeepsThePortfolioInTheList() {
        let s = makeStorage([Portfolio(name: "Fantasy", holdings: [holding("AAPL", qty: 10, avg: 100)])])
        let id = s.portfolios[0].id
        s.setExcludedFromTotal(true, id: id)
        XCTAssertEqual(s.portfolios.count, 1)
        XCTAssertEqual(s.portfolios[0].holdings.count, 1)
        XCTAssertTrue(s.portfolios[0].isExcludedFromTotal)
        XCTAssertTrue(s.countedPortfolios.isEmpty)
    }

    func testToggleBackIncludesItAgain() {
        let s = makeStorage([Portfolio(name: "Fantasy", holdings: [], excludedFromTotal: true)])
        let id = s.portfolios[0].id
        s.setExcludedFromTotal(false, id: id)
        XCTAssertFalse(s.portfolios[0].isExcludedFromTotal)
        XCTAssertEqual(s.countedPortfolios.count, 1)
    }

    func testSettingOnAnUnknownIdIsANoOp() {
        let s = makeStorage([Portfolio(name: "Real")])
        s.setExcludedFromTotal(true, id: UUID())
        XCTAssertEqual(s.countedPortfolios.count, 1)
    }

    // MARK: - The aggregate the totals are built from

    /// The figure every combined total is derived from (menu bar, All Portfolios,
    /// window footer) must ignore the excluded portfolio's holdings.
    func testValuationOverCountedPortfoliosExcludesTheFantasyHoldings() {
        let s = makeStorage([
            Portfolio(name: "Real", holdings: [holding("AAPL", qty: 10, avg: 100)]),
            Portfolio(name: "Fantasy", holdings: [holding("TSLA", qty: 5, avg: 200)], excludedFromTotal: true),
        ])

        let inputs = s.countedPortfolios.flatMap(\.holdings).map {
            PortfolioValuation.Input(holding: $0, price: 150, rate: 1, costRate: 1)
        }
        let totals = PortfolioValuation.totals(inputs)

        // Only the real position: 10 × 150 value, 10 × 100 cost.
        XCTAssertEqual(totals.value, 1500, accuracy: 0.001)
        XCTAssertEqual(totals.cost, 1000, accuracy: 0.001)
    }

    /// Same data, nothing excluded: the fantasy position is now inside the total.
    /// Guards against the filter being a no-op in the wrong direction.
    func testValuationIncludesEverythingWhenNothingIsExcluded() {
        let s = makeStorage([
            Portfolio(name: "Real", holdings: [holding("AAPL", qty: 10, avg: 100)]),
            Portfolio(name: "Paper", holdings: [holding("TSLA", qty: 5, avg: 200)]),
        ])

        let inputs = s.countedPortfolios.flatMap(\.holdings).map {
            PortfolioValuation.Input(holding: $0, price: 150, rate: 1, costRate: 1)
        }
        let totals = PortfolioValuation.totals(inputs)

        XCTAssertEqual(totals.value, 2250, accuracy: 0.001)   // (10 + 5) × 150
        XCTAssertEqual(totals.cost, 2000, accuracy: 0.001)    // 10×100 + 5×200
    }
}
