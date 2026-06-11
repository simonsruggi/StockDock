import XCTest
@testable import StockDock

/// Regression tests for the "quintali di notifiche" bug: portfolio notifications
/// re-firing on every tick when the value oscillates around a step/milestone boundary.
/// The intended behaviour is "smart anti-spam": only genuinely NEW extremes notify;
/// hovering or retracing must stay silent.
final class NotificationAntiSpamTests: XCTestCase {

    // MARK: - Daily step oscillation (dailyPercent / dailyAbsolute)

    /// Once step 2 has been announced today, retracing into the step-1 band must NOT
    /// re-fire — the user already passed step 1 on the way up.
    func testStepDoesNotRefireWhenRetracingSameDirection() {
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 1.5, threshold: 1, lastUp: 2, lastDown: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 1.0, threshold: 1, lastUp: 2, lastDown: nil))
    }

    /// Hovering at the +2% boundary (1.99 ↔ 2.01) must produce at most the first +2,
    /// never a stream of alternating +1/+2.
    func testStepHoveringAtBoundaryDoesNotSpam() {
        // already announced +2 today
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 1.99, threshold: 1, lastUp: 2, lastDown: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 2.01, threshold: 1, lastUp: 2, lastDown: nil))
    }

    /// A genuinely higher step still fires.
    func testStepStillFiresOnNewHigh() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: 3.1, threshold: 1, lastUp: 2, lastDown: nil), 3)
    }

    /// First move into the negative side fires once, then negative hovering is silent,
    /// even though the positive high-water remains recorded.
    func testStepFiresFirstNegativeThenSilent() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: -1.2, threshold: 1, lastUp: 2, lastDown: nil), -1)
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: -1.2, threshold: 1, lastUp: 2, lastDown: -1))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: -0.8, threshold: 1, lastUp: 2, lastDown: -1))
    }

    /// Zero-cross oscillation (+1 ↔ -1) must not spam once both sides are known.
    func testStepZeroCrossOscillationDoesNotSpam() {
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 1.2, threshold: 1, lastUp: 1, lastDown: -1))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: -1.2, threshold: 1, lastUp: 1, lastDown: -1))
    }

    // MARK: - Milestone oscillation

    /// After reaching the 60k milestone, dropping back into the 50k band must NOT
    /// re-announce 50k (already passed on the way up).
    func testMilestoneDoesNotRefireWhenRetracing() {
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 55_000, step: 10_000, highest: 60_000, lowest: 50_000))
    }

    /// Hovering at the 60k boundary must not stream up/down notifications.
    func testMilestoneHoveringAtBoundaryDoesNotSpam() {
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 59_999, step: 10_000, highest: 60_000, lowest: 50_000))
        XCTAssertNil(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 60_001, step: 10_000, highest: 60_000, lowest: 50_000))
    }

    /// A genuinely new high / new low still fires.
    func testMilestoneFiresOnNewExtremes() {
        XCTAssertEqual(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 71_000, step: 10_000, highest: 60_000, lowest: 50_000), 70_000)
        XCTAssertEqual(PortfolioAlertEvaluator.milestoneCrossed(totalValue: 48_000, step: 10_000, highest: 60_000, lowest: 50_000), 40_000)
    }

    // MARK: - NotificationManager burst de-dup (blanket backstop for all types)

    func testDeliversWhenNeverSentBefore() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(NotificationManager.shouldDeliver(identifier: "a", now: now, lastSent: nil, window: 120))
    }

    func testSuppressesExactDuplicateWithinWindow() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = t0.addingTimeInterval(5)   // 5s later — within the 120s window
        XCTAssertFalse(NotificationManager.shouldDeliver(identifier: "a", now: t1, lastSent: t0, window: 120))
    }

    func testDeliversAgainAfterWindowElapsed() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = t0.addingTimeInterval(120)
        XCTAssertTrue(NotificationManager.shouldDeliver(identifier: "a", now: t1, lastSent: t0, window: 120))
    }
}
