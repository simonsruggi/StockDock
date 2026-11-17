import XCTest
@testable import StockDock

/// The chart ranges shared by the symbol and portfolio charts: where each one
/// starts and which points it keeps.
final class ChartRangeTests: XCTestCase {
    private let cal = Calendar.current

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    private func daily(from start: Date, count: Int) -> [PricePoint] {
        (0..<count).map { PricePoint(date: cal.date(byAdding: .day, value: $0, to: start)!, close: Double(100 + $0)) }
    }

    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12))!

    func testYTDStartsOnJanuaryFirst() {
        let cutoff = ChartRange.ytd.cutoff(now: now)!
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: cutoff),
                       DateComponents(year: 2026, month: 1, day: 1))
    }

    /// The year's change is measured from last year's final close, so YTD keeps
    /// the last point before January 1st as its first point.
    func testYTDKeepsLastYearsFinalClose() {
        let series = daily(from: date(2025, 12, 20), count: 30)
        let ytd = ChartRange.ytd.slice(series, date: \.date, now: now)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: ytd.first!.date),
                       DateComponents(year: 2025, month: 12, day: 31))
        XCTAssertEqual(ytd.dropFirst().allSatisfy { cal.component(.year, from: $0.date) == 2026 }, true)
    }

    /// A symbol listed this year has no point before January 1st: YTD is just its own points.
    func testYTDWithoutHistoryBeforeTheYear() {
        let series = daily(from: date(2026, 3, 1), count: 10)
        XCTAssertEqual(ChartRange.ytd.slice(series, date: \.date, now: now), series)
    }

    func testFixedWindowsCutByDays() {
        let series = daily(from: date(2024, 11, 17), count: 731)
        for (range, days) in [(ChartRange.month, 30), (.threeMonths, 91), (.sixMonths, 182), (.year, 365)] {
            let cutoff = cal.date(byAdding: .day, value: -days, to: now)!
            let sliced = range.slice(series, date: \.date, now: now)
            XCTAssertTrue(sliced.allSatisfy { $0.date >= cutoff }, "\(range.rawValue)")
            XCTAssertEqual(sliced.count, series.filter { $0.date >= cutoff }.count, "\(range.rawValue)")
        }
    }

    func testAllKeepsTheWholeSeries() {
        let series = daily(from: date(2020, 1, 1), count: 50)
        XCTAssertEqual(ChartRange.all.slice(series, date: \.date, now: now), series)
    }

    func testOnlyFiveYearsAndAllNeedTheLongSeries() {
        XCTAssertEqual(ChartRange.allCases.filter(\.needsLongHistory), [.fiveYears, .all])
    }

    func testPillLabels() {
        XCTAssertEqual(ChartRange.day.changeLabel, "today")
        XCTAssertEqual(ChartRange.threeMonths.changeLabel, "past 3M")
        XCTAssertEqual(ChartRange.ytd.changeLabel, "this year")
        XCTAssertEqual(ChartRange.fiveYears.changeLabel, "past 5Y")
        XCTAssertEqual(ChartRange.all.changeLabel, "all-time")
    }

    /// Stored ranges from older versions still restore.
    func testOldStoredValuesStillDecode() {
        for raw in ["24H", "7D", "1M", "1Y", "All"] { XCTAssertNotNil(ChartRange(rawValue: raw), raw) }
    }
}
