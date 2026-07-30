import XCTest
@testable import StockDock

/// Covers the estimated portfolio-value backfill: reconstruct a past value curve
/// from each holding's real price history × current position, so the Overview
/// chart isn't empty on day one. Only days where EVERY holding has a close count
/// (a partial day would understate the total).
final class PortfolioBackfillTests: XCTestCase {

    private func day(_ d: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(d * 86400)) }
    private func h(_ symbol: String, qty: Double, leverage: Double? = nil, bought: Date? = nil) -> Holding {
        Holding(symbol: symbol, quantity: qty, avgPrice: 1, purchaseDate: bought, leverage: leverage)
    }

    /// Local midnight anchors: the purchase-date clamp normalises with
    /// `Calendar.current.startOfDay`, so building both the bars and the purchase
    /// timestamps off local days keeps these tests timezone-independent.
    private func localDay(_ d: Int) -> Date { Calendar.current.startOfDay(for: day(d)) }
    /// A price bar mid-session on local day `d`.
    private func bar(_ d: Int, _ close: Double) -> PricePoint {
        PricePoint(date: localDay(d).addingTimeInterval(12 * 3600), close: close)
    }
    /// A purchase made in the afternoon of local day `d`.
    private func bought(_ d: Int) -> Date { localDay(d).addingTimeInterval(15 * 3600) }

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

    // MARK: - Purchase-date window

    /// The curve must not reach back before the position existed: a symbol with
    /// decades of price history bought last month starts last month, not at its IPO.
    func testCurveStartsAtPurchaseDate() {
        let holdings = [h("A", qty: 10, bought: bought(3))]
        let history = ["A": [bar(1, 1), bar(2, 2), bar(3, 3), bar(4, 4)]]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1])
        XCTAssertEqual(series.map(\.date), [bar(3, 0).date, bar(4, 0).date])
        XCTAssertEqual(series.map(\.value), [30, 40])
    }

    /// Each position counts only from its own purchase date, so the curve steps up
    /// as the portfolio was actually built instead of valuing every lot since day one.
    func testHoldingCountsOnlyFromItsOwnPurchaseDate() {
        let holdings = [h("A", qty: 10, bought: bought(1)), h("B", qty: 2, bought: bought(3))]
        let history = [
            "A": [bar(1, 5), bar(2, 5), bar(3, 5)],
            "B": [bar(1, 100), bar(2, 100), bar(3, 100)],
        ]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1, "B": 1])
        XCTAssertEqual(series.map(\.value), [50, 50, 250]) // B only joins on day 3
    }

    /// Holdings saved before purchase dates existed (or imported without one) must
    /// keep the old behaviour: valued across the whole available window.
    func testMissingPurchaseDateKeepsFullWindow() {
        let holdings = [h("A", qty: 10, bought: bought(3)), h("B", qty: 1)] // B has no date
        let history = ["A": [bar(2, 5), bar(3, 5)], "B": [bar(2, 7), bar(3, 7)]]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1, "B": 1])
        // Window starts at A's purchase (the oldest date on record); B counts there.
        XCTAssertEqual(series.map(\.value), [57])
    }

    /// A purchase later than every available bar leaves nothing to draw rather than
    /// falling back to the full history.
    func testPurchaseAfterHistoryYieldsEmpty() {
        let holdings = [h("A", qty: 10, bought: bought(9))]
        let history = ["A": [bar(1, 5), bar(2, 6)]]
        XCTAssertTrue(PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1]).isEmpty)
    }

    func testChronological() {
        let holdings = [h("A", qty: 1)]
        let history = ["A": [PricePoint(date: day(3), close: 3), PricePoint(date: day(1), close: 1)]]
        let series = PortfolioBackfill.series(holdings: holdings, historyBySymbol: history, rateBySymbol: ["A": 1])
        XCTAssertEqual(series.map(\.value), [1, 3])
    }
}
