import XCTest
@testable import StockDock

/// Covers the estimated portfolio-value backfill: reconstruct a past value curve
/// from each holding's real price history × current position, so the Overview
/// chart isn't empty on day one. Only days where EVERY holding has a close count
/// (a partial day would understate the total).
final class PortfolioBackfillTests: XCTestCase {

    private func day(_ d: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(d * 86400)) }
    private func h(_ symbol: String, qty: Double, leverage: Double? = nil) -> Holding {
        Holding(symbol: symbol, quantity: qty, avgPrice: 1, leverage: leverage)
    }

    func testSingleHoldingCurve() {
        let holdings = [h("A", qty: 10)]
        let history = ["A": [PricePoint(date: day(1), close: 5), PricePoint(date: day(2), close: 6)]]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1])
        XCTAssertEqual(series.map(\.value), [50, 60])
        XCTAssertEqual(series.map(\.date), [day(1), day(2)])
    }

    func testAppliesRate() {
        let holdings = [h("A", qty: 10)]
        let history = ["A": [PricePoint(date: day(1), close: 5)]]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 0.9])
        XCTAssertEqual(series.first?.value ?? 0, 45, accuracy: 1e-9)
    }

    func testSumsHoldingsOnCommonDaysOnly() {
        let holdings = [h("A", qty: 10), h("B", qty: 2)]
        let history = [
            "A": [PricePoint(date: day(1), close: 5), PricePoint(date: day(2), close: 6)],
            "B": [PricePoint(date: day(2), close: 100)], // no day 1 → day 1 excluded
        ]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1, "B": 1])
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.first?.date, day(2))
        XCTAssertEqual(series.first?.value ?? 0, 6 * 10 + 100 * 2, accuracy: 1e-9) // 260
    }

    func testLeverageAndShort() {
        let holdings = [h("A", qty: -10, leverage: 2)] // short 10, 2×
        let history = ["A": [PricePoint(date: day(1), close: 5)]]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1])
        XCTAssertEqual(series.first?.value ?? 0, 5 * -10 * 2, accuracy: 1e-9) // -100
    }

    func testEmptyWhenNoHistory() {
        let series = PortfolioBackfill.series(holdings: [h("A", qty: 1)], historyBySymbol: [:], rateBySymbol: [:])
        XCTAssertTrue(series.isEmpty)
    }

    func testChronological() {
        let holdings = [h("A", qty: 1)]
        let history = ["A": [PricePoint(date: day(3), close: 3), PricePoint(date: day(1), close: 1)]]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1])
        XCTAssertEqual(series.map(\.value), [1, 3])
    }
}
