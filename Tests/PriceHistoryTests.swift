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
}
