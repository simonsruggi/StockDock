import XCTest
@testable import StockDock

final class PortfolioAlertEvaluatorTests: XCTestCase {

    // MARK: - crossingStep (used by dailyPercent / dailyAbsolute)

    func testNoFireWithinThreshold() {
        // value below ±threshold → no step crossed
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 0.9, threshold: 1, lastUp: nil, lastDown: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: -0.9, threshold: 1, lastUp: nil, lastDown: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 0, threshold: 1, lastUp: nil, lastDown: nil))
    }

    func testFiresOnFirstCrossingUp() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 1.0, threshold: 1, lastUp: nil, lastDown: nil), 1)
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 3.2, threshold: 1, lastUp: nil, lastDown: nil), 3)
    }

    func testFiresOnFirstCrossingDown() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: -1.0, threshold: 1, lastUp: nil, lastDown: nil), -1)
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: -2.7, threshold: 1, lastUp: nil, lastDown: nil), -2)
    }

    func testDoesNotRefireSameStep() {
        // already fired step 3, value still in [3,4) → no new fire
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 3.5, threshold: 1, lastUp: 3, lastDown: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 3.0, threshold: 1, lastUp: 3, lastDown: nil))
    }

    func testRefiresOnNextStepUp() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 4.1, threshold: 1, lastUp: 3, lastDown: nil), 4)
    }

    func testFiresWhenReversingDirection() {
        // was +3 (up high-water), now dropped to -1 → first negative step fires
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: -1.2, threshold: 1, lastUp: 3, lastDown: nil), -1)
    }

    func testRespectsCustomThresholdSize() {
        // absolute mode: threshold 250 currency units
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 249, threshold: 250, lastUp: nil, lastDown: nil))
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 250, threshold: 250, lastUp: nil, lastDown: nil), 1)
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 760, threshold: 250, lastUp: nil, lastDown: nil), 3)
    }

    func testInvalidThresholdNeverFires() {
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 100, threshold: 0, lastUp: nil, lastDown: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 100, threshold: -1, lastUp: nil, lastDown: nil))
    }

    // MARK: - milestoneCrossed

    func testMilestoneFloorValue() {
        // value 53_200 with step 10_000 → milestone 50_000 (first observation primes)
        XCTAssertEqual(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 53_200, step: 10_000, highest: nil, lowest: nil), 50_000)
    }

    func testMilestoneDoesNotRefireSameLevel() {
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 54_000, step: 10_000, highest: 50_000, lowest: 50_000))
    }

    func testMilestoneFiresOnNewLevelUp() {
        XCTAssertEqual(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 61_000, step: 10_000, highest: 50_000, lowest: 50_000), 60_000)
    }

    func testMilestoneFiresOnNewLevelDown() {
        XCTAssertEqual(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 48_000, step: 10_000, highest: 50_000, lowest: 50_000), 40_000)
    }

    func testMilestoneInvalidInputs() {
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 0, step: 10_000, highest: nil, lowest: nil))
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 5_000, step: 0, highest: nil, lowest: nil))
        // value below first milestone step → nothing to cross
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 5_000, step: 10_000, highest: nil, lowest: nil))
    }

    // MARK: - shouldFireSummary

    func testSummaryFiresOncePerDayAfterClose() {
        XCTAssertTrue(PortfolioAlertEvaluator.shouldFireSummary(today: "2026-06-08", lastDay: nil, isAfterClose: true))
        XCTAssertTrue(PortfolioAlertEvaluator.shouldFireSummary(today: "2026-06-08", lastDay: "2026-06-07", isAfterClose: true))
    }

    func testSummaryDoesNotFireTwiceSameDay() {
        XCTAssertFalse(PortfolioAlertEvaluator.shouldFireSummary(today: "2026-06-08", lastDay: "2026-06-08", isAfterClose: true))
    }

    func testSummaryDoesNotFireBeforeClose() {
        XCTAssertFalse(PortfolioAlertEvaluator.shouldFireSummary(today: "2026-06-08", lastDay: nil, isAfterClose: false))
    }
}
