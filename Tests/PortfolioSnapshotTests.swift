import XCTest
@testable import StockDock

/// Covers the historical-snapshot foundation for the Portfolio window:
/// (1) portfolio valuation aggregation (value + cost in the preferred currency,
/// reusing the signed/leverage-aware `Holding` math), and (2) the one-per-day
/// snapshot log (append a new day, replace the same day so the latest intraday
/// value wins). The log accumulates forward — there is no historical backfill.
final class PortfolioSnapshotTests: XCTestCase {

    private func input(qty: Double, avg: Double, price: Double, rate: Double = 1, costRate: Double = 1, leverage: Double? = nil) -> PortfolioValuation.Input {
        PortfolioValuation.Input(
            holding: Holding(symbol: "X", quantity: qty, avgPrice: avg, leverage: leverage),
            price: price, rate: rate, costRate: costRate
        )
    }

    // MARK: - Valuation

    func testTotalsAggregatesLongPositions() {
        let totals = PortfolioValuation.totals([
            input(qty: 10, avg: 100, price: 120), // value 1200, cost 1000
            input(qty: 5,  avg: 50,  price: 60),  // value 300,  cost 250
        ])
        XCTAssertEqual(totals.value, 1500, accuracy: 1e-9)
        XCTAssertEqual(totals.cost, 1250, accuracy: 1e-9)
    }

    func testTotalsAppliesExchangeRates() {
        // A USD holding valued in EUR: current rate 0.90, purchase-date rate 0.85.
        let totals = PortfolioValuation.totals([
            input(qty: 10, avg: 100, price: 120, rate: 0.90, costRate: 0.85)
        ])
        XCTAssertEqual(totals.value, 1200 * 0.90, accuracy: 1e-9)
        XCTAssertEqual(totals.cost, 1000 * 0.85, accuracy: 1e-9)
    }

    func testTotalsRespectsShortAndLeverage() {
        // Short 10 @ 100, price 80, 2× leverage → market value = 80*-10*2 = -1600,
        // cost basis = 100*-10*2 = -2000. P&L (value-cost) = +400 (short profit).
        let totals = PortfolioValuation.totals([
            input(qty: -10, avg: 100, price: 80, leverage: 2)
        ])
        XCTAssertEqual(totals.value, -1600, accuracy: 1e-9)
        XCTAssertEqual(totals.cost, -2000, accuracy: 1e-9)
        let snap = PortfolioSnapshot(date: Date(timeIntervalSince1970: 0), totalValue: totals.value, totalCost: totals.cost)
        XCTAssertEqual(snap.totalPnl, 400, accuracy: 1e-9)
    }

    func testEmptyPortfolioIsZero() {
        let totals = PortfolioValuation.totals([])
        XCTAssertEqual(totals.value, 0)
        XCTAssertEqual(totals.cost, 0)
    }

    // MARK: - Snapshot derived metrics

    func testPnlPercentUsesMagnitudeOfCost() {
        let snap = PortfolioSnapshot(date: Date(), totalValue: 1250, totalCost: 1000)
        XCTAssertEqual(snap.totalPnl, 250, accuracy: 1e-9)
        XCTAssertEqual(snap.pnlPercent, 25, accuracy: 1e-9)
    }

    func testPnlPercentIsZeroWhenCostNegligible() {
        let snap = PortfolioSnapshot(date: Date(), totalValue: 500, totalCost: 0)
        XCTAssertEqual(snap.pnlPercent, 0)
    }

    // MARK: - One-per-day log

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    func testUpsertAppendsNewDay() {
        var log: [PortfolioSnapshot] = []
        log = SnapshotLog.upsert(PortfolioSnapshot(date: day(2026, 7, 14), totalValue: 100, totalCost: 90), into: log)
        log = SnapshotLog.upsert(PortfolioSnapshot(date: day(2026, 7, 15), totalValue: 110, totalCost: 90), into: log)
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log.map(\.totalValue), [100, 110]) // chronological
    }

    func testUpsertReplacesSameDayWithLatestValue() {
        var log: [PortfolioSnapshot] = []
        // Morning value, then an afternoon refresh the same day.
        log = SnapshotLog.upsert(PortfolioSnapshot(date: day(2026, 7, 15), totalValue: 100, totalCost: 90), into: log)
        log = SnapshotLog.upsert(PortfolioSnapshot(date: day(2026, 7, 15), totalValue: 137, totalCost: 90), into: log)
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log[0].totalValue, 137, accuracy: 1e-9)
    }

    func testUpsertKeepsChronologicalOrderWhenBackfilling() {
        var log: [PortfolioSnapshot] = []
        log = SnapshotLog.upsert(PortfolioSnapshot(date: day(2026, 7, 15), totalValue: 110, totalCost: 90), into: log)
        // An out-of-order insert (e.g. clock skew) still sorts correctly.
        log = SnapshotLog.upsert(PortfolioSnapshot(date: day(2026, 7, 14), totalValue: 100, totalCost: 90), into: log)
        XCTAssertEqual(log.map(\.totalValue), [100, 110])
    }

    func testIsNewDay() {
        let log = [PortfolioSnapshot(date: day(2026, 7, 15), totalValue: 100, totalCost: 90)]
        XCTAssertFalse(SnapshotLog.isNewDay(day(2026, 7, 15), in: log))
        XCTAssertTrue(SnapshotLog.isNewDay(day(2026, 7, 16), in: log))
    }
}
