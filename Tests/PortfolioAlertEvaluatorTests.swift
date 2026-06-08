import XCTest
@testable import StockDock

final class PortfolioAlertEvaluatorTests: XCTestCase {

    // MARK: - crossingStep (used by dailyPercent / dailyAbsolute)

    func testNoFireWithinThreshold() {
        // value below ±threshold → no step crossed
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 0.9, threshold: 1, lastStep: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: -0.9, threshold: 1, lastStep: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 0, threshold: 1, lastStep: nil))
    }

    func testFiresOnFirstCrossingUp() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 1.0, threshold: 1, lastStep: nil), 1)
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 3.2, threshold: 1, lastStep: nil), 3)
    }

    func testFiresOnFirstCrossingDown() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: -1.0, threshold: 1, lastStep: nil), -1)
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: -2.7, threshold: 1, lastStep: nil), -2)
    }

    func testDoesNotRefireSameStep() {
        // already fired step 3, value still in [3,4) → no new fire
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 3.5, threshold: 1, lastStep: 3))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 3.0, threshold: 1, lastStep: 3))
    }

    func testRefiresOnNextStepUp() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 4.1, threshold: 1, lastStep: 3), 4)
    }

    func testFiresWhenReversingDirection() {
        // was +3, now dropped to -1 → crosses a new (negative) step
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: -1.2, threshold: 1, lastStep: 3), -1)
    }

    func testRespectsCustomThresholdSize() {
        // absolute mode: threshold 250 currency units
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 249, threshold: 250, lastStep: nil))
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 250, threshold: 250, lastStep: nil), 1)
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 760, threshold: 250, lastStep: nil), 3)
    }

    func testInvalidThresholdNeverFires() {
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 100, threshold: 0, lastStep: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 100, threshold: -1, lastStep: nil))
    }

    // MARK: - milestoneCrossed

    func testMilestoneFloorValue() {
        // value 53_200 with step 10_000 → milestone 50_000
        XCTAssertEqual(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 53_200, step: 10_000, lastMilestone: nil), 50_000)
    }

    func testMilestoneDoesNotRefireSameLevel() {
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 54_000, step: 10_000, lastMilestone: 50_000))
    }

    func testMilestoneFiresOnNewLevelUp() {
        XCTAssertEqual(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 61_000, step: 10_000, lastMilestone: 50_000), 60_000)
    }

    func testMilestoneFiresOnNewLevelDown() {
        XCTAssertEqual(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 48_000, step: 10_000, lastMilestone: 50_000), 40_000)
    }

    func testMilestoneInvalidInputs() {
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 0, step: 10_000, lastMilestone: nil))
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 5_000, step: 0, lastMilestone: nil))
        // value below first milestone step → nothing to cross
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 5_000, step: 10_000, lastMilestone: nil))
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
