import XCTest
@testable import StockDock

/// Covers the pure pairing of Yahoo v8 chart arrays (timestamps + closes with
/// possible nil holes) into chartable daily price points.
final class PriceHistoryTests: XCTestCase {

    func testPairsTimestampsWithCloses() {
        let points = PriceHistory.points(timestamps: [1000, 2000, 3000],
                                         closes: [10.0, 11.5, 12.0])
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].date, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(points[0].close, 10.0, accuracy: 1e-9)
        XCTAssertEqual(points[2].close, 12.0, accuracy: 1e-9)
    }

    func testSkipsNilCloses() {
        // Yahoo leaves nil holes on holidays/halts — they must not become zeros.
        let points = PriceHistory.points(timestamps: [1000, 2000, 3000],
                                         closes: [10.0, nil, 12.0])
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.map(\.close), [10.0, 12.0])
    }

    func testTruncatesToShortestArray() {
        // Defensive: mismatched lengths pair only the overlapping prefix.
        let points = PriceHistory.points(timestamps: [1000, 2000],
                                         closes: [10.0, 11.0, 12.0])
        XCTAssertEqual(points.count, 2)
        let points2 = PriceHistory.points(timestamps: [1000, 2000, 3000],
                                          closes: [10.0])
        XCTAssertEqual(points2.count, 1)
    }

    func testEmptyInputs() {
        XCTAssertTrue(PriceHistory.points(timestamps: [], closes: []).isEmpty)
    }

    func testPointsAreChronological() {
        let points = PriceHistory.points(timestamps: [3000, 1000, 2000],
                                         closes: [12.0, 10.0, 11.0])
        XCTAssertEqual(points.map(\.close), [10.0, 11.0, 12.0])
    }

    // MARK: - lastSession

    /// 5-minute bars starting at `start`, contiguous.
    private func bars(from start: Int, count: Int, firstClose: Double) -> [PricePoint] {
        (0..<count).map { i in
            PricePoint(date: Date(timeIntervalSince1970: TimeInterval(start + i * 300)),
                       close: firstClose + Double(i))
        }
    }

    func testLastSessionKeepsOnlyTheMostRecentDay() {
        // Two sessions ~17h apart (yesterday's close → today's open). Asking for
        // two days of bars must still chart one day.
        let yesterday = bars(from: 1_000_000, count: 6, firstClose: 100)
        let today = bars(from: 1_000_000 + 86_400, count: 4, firstClose: 200)
        let session = PriceHistory.lastSession(yesterday + today)
        XCTAssertEqual(session.count, 4)
        XCTAssertEqual(session.map(\.close), [200, 201, 202, 203])
    }

    func testLastSessionLeavesASingleSessionIntact() {
        let day = bars(from: 1_000_000, count: 78, firstClose: 50)
        XCTAssertEqual(PriceHistory.lastSession(day).count, 78)
    }

    /// The regression behind the empty 24H chart: before the open (and on
    /// weekends/holidays) Yahoo has no bars for today, so the only session in
    /// the payload is the previous one — it must be charted, not discarded.
    func testLastSessionFallsBackToThePreviousSessionWhenTodayHasNoBars() {
        let previous = bars(from: 1_000_000, count: 78, firstClose: 100)
        let session = PriceHistory.lastSession(previous)
        XCTAssertEqual(session.count, 78)
        XCTAssertEqual(session.last?.close, previous.last?.close)
    }

    func testLastSessionDoesNotSplitOnTheLunchGapOfAThinlyTradedSymbol() {
        // A 30-minute hole (no prints) is not a new session.
        let morning = bars(from: 1_000_000, count: 10, firstClose: 10)
        let afternoon = bars(from: 1_000_000 + 10 * 300 + 1_800, count: 10, firstClose: 20)
        XCTAssertEqual(PriceHistory.lastSession(morning + afternoon).count, 20)
    }

    func testLastSessionOnEmptyInput() {
        XCTAssertTrue(PriceHistory.lastSession([]).isEmpty)
    }
}
