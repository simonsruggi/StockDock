import XCTest
@testable import StockDock

/// Regression tests for the "quintali di notifiche" bug: portfolio notifications
/// firing too often. Daily-move notifications must fire at most once per direction
/// per day (first +threshold crossing, first -threshold crossing); a trending or
/// oscillating day must NOT produce a stream.
final class NotificationAntiSpamTests: XCTestCase {

    /// Mirrors PortfolioMonitor.evaluateDailyStep state threading for a single day:
    /// scope marks reset at day start (passed in as nil), fire via crossingStep,
    /// advance only the side that fired. Returns how many notifications the sequence
    /// would emit — the end-to-end anti-spam assertion.
    private func dailyFireCount(_ values: [Double], threshold: Double) -> Int {
        var lastUp: Double? = nil
        var lastDown: Double? = nil
        var count = 0
        for v in values {
            guard let step = PortfolioAlertEvaluator.crossingStep(value: v, threshold: threshold, lastUp: lastUp, lastDown: lastDown) else { continue }
            count += 1
            if step > 0 { lastUp = step } else { lastDown = step }
        }
        return count
    }

    // MARK: - Daily move: at most one up + one down per day

    /// A steadily climbing day (+1.1 … +4.9%) must fire ONCE, not once per step.
    /// This is the "too many notifications" regression.
    func testTrendingUpDayFiresOnce() {
        XCTAssertEqual(dailyFireCount([1.1, 2.3, 3.6, 4.9], threshold: 1), 1)
    }

    /// A full swing — up through +threshold then down through -threshold — fires
    /// exactly one up and one down.
    func testSwingFiresOnceEachDirection() {
        XCTAssertEqual(dailyFireCount([1.1, 2.3, -1.2, -2.5], threshold: 1), 2)
    }

    /// All-day oscillation around both boundaries still caps at one up + one down.
    func testOscillatingDayCapsAtTwo() {
        XCTAssertEqual(dailyFireCount([1.2, 0.5, 1.8, 0.3, 2.9, -1.1, -0.2, -3.0, -0.5, 1.5], threshold: 1), 2)
    }

    /// Absolute mode (currency threshold) behaves identically.
    func testAbsoluteModeTrendingDayFiresOnce() {
        XCTAssertEqual(dailyFireCount([260, 540, 820, 1100], threshold: 250), 1)
    }

    // MARK: - crossingStep direction gate

    /// Once the up side has fired today, higher values stay silent until tomorrow.
    func testUpSideSilentAfterFiring() {
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 3.1, threshold: 1, lastUp: 1, lastDown: nil))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: 1.0, threshold: 1, lastUp: 1, lastDown: nil))
    }

    /// First move into the negative side fires once, then the down side is silent,
    /// independently of whether the up side already fired.
    func testDownSideFiresOnceThenSilent() {
        XCTAssertEqual(PortfolioAlertEvaluator.crossingStep(value: -1.2, threshold: 1, lastUp: 1, lastDown: nil), -1)
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: -2.4, threshold: 1, lastUp: 1, lastDown: -1))
        XCTAssertNil(PortfolioAlertEvaluator.crossingStep(value: -0.8, threshold: 1, lastUp: 1, lastDown: -1))
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
