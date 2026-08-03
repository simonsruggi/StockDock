import XCTest
@testable import StockDock

/// Covers short positions (negative quantity) and leverage (P&L/exposure
/// multiplier). Both are gated behind the "Advanced" setting in the UI, but the
/// math lives on `Holding` and must be correct in every quadrant:
/// long/short × profit/loss, with and without leverage.
final class ShortLeverageTests: XCTestCase {

    private func holding(qty: Double, avg: Double, leverage: Double? = nil) -> Holding {
        Holding(symbol: "X", quantity: qty, avgPrice: avg, leverage: leverage)
    }

    // MARK: - Long (baseline, unchanged behaviour)

    func testLongProfit() {
        let h = holding(qty: 10, avg: 100)
        XCTAssertEqual(h.pnl(currentPrice: 120), 200, accuracy: 1e-9)
        XCTAssertEqual(h.marketValue(currentPrice: 120), 1200, accuracy: 1e-9)
        XCTAssertEqual(h.pnlPercent(currentPrice: 120), 20, accuracy: 1e-9)
        XCTAssertEqual(h.costBasisLocal, 1000, accuracy: 1e-9)
    }

    func testLongLoss() {
        let h = holding(qty: 10, avg: 100)
        XCTAssertEqual(h.pnl(currentPrice: 80), -200, accuracy: 1e-9)
        XCTAssertEqual(h.pnlPercent(currentPrice: 80), -20, accuracy: 1e-9)
    }

    // MARK: - Short (negative quantity)

    func testShortProfitWhenPriceFalls() {
        // Short 10 @ 100, price drops to 80 → +200 gain, shown as +20%.
        let h = holding(qty: -10, avg: 100)
        XCTAssertEqual(h.pnl(currentPrice: 80), 200, accuracy: 1e-9)
        XCTAssertEqual(h.pnlPercent(currentPrice: 80), 20, accuracy: 1e-9)
        XCTAssertEqual(h.marketValue(currentPrice: 80), -800, accuracy: 1e-9)
        XCTAssertEqual(h.costBasisLocal, -1000, accuracy: 1e-9)
    }

    func testShortLossWhenPriceRises() {
        // Short 10 @ 100, price rises to 120 → -200 loss, shown as -20%.
        let h = holding(qty: -10, avg: 100)
        XCTAssertEqual(h.pnl(currentPrice: 120), -200, accuracy: 1e-9)
        XCTAssertEqual(h.pnlPercent(currentPrice: 120), -20, accuracy: 1e-9)
    }

    // MARK: - Leverage (P&L / exposure multiplier)

    func testDefaultLeverageIsOne() {
        XCTAssertEqual(holding(qty: 1, avg: 1).effectiveLeverage, 1, accuracy: 1e-9)
        XCTAssertEqual(holding(qty: 1, avg: 1, leverage: 3).effectiveLeverage, 3, accuracy: 1e-9)
    }

    func testLeverageAmplifiesPnlAndExposure() {
        // Long 10 @ 100 at 3x, price 110.
        let h = holding(qty: 10, avg: 100, leverage: 3)
        XCTAssertEqual(h.pnl(currentPrice: 110), 300, accuracy: 1e-9)        // 10×10×3
        XCTAssertEqual(h.marketValue(currentPrice: 110), 3300, accuracy: 1e-9) // 110×10×3
        XCTAssertEqual(h.costBasisLocal, 3000, accuracy: 1e-9)               // 100×10×3
        // Per-position % is exposure-relative, so leverage cancels out.
        XCTAssertEqual(h.pnlPercent(currentPrice: 110), 10, accuracy: 1e-9)
    }

    func testLeveragedShort() {
        // Short 5 @ 100 at 2x, price drops to 90 → +100 gain.
        let h = holding(qty: -5, avg: 100, leverage: 2)
        XCTAssertEqual(h.pnl(currentPrice: 90), 100, accuracy: 1e-9)         // (90-100)×-5×2
        XCTAssertEqual(h.marketValue(currentPrice: 90), -900, accuracy: 1e-9)
        XCTAssertEqual(h.costBasisLocal, -1000, accuracy: 1e-9)
        XCTAssertEqual(h.pnlPercent(currentPrice: 90), 10, accuracy: 1e-9)
    }

    func testDailyPnlRespectsDirectionAndLeverage() {
        XCTAssertEqual(holding(qty: 10, avg: 100, leverage: 2).dailyPnl(priceChange: 3), 60, accuracy: 1e-9)
        XCTAssertEqual(holding(qty: -10, avg: 100, leverage: 2).dailyPnl(priceChange: 3), -60, accuracy: 1e-9)
    }

    // MARK: - Edge cases

    func testZeroAvgPriceGivesZeroPercent() {
        XCTAssertEqual(holding(qty: 10, avg: 0).pnlPercent(currentPrice: 50), 0, accuracy: 1e-9)
    }
}
