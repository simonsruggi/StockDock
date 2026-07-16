import XCTest
@testable import StockDock

/// Issue #11: the reporter wants the Home/News tab gone entirely. `Tab.visible`
/// is the single source of truth for which tabs render, so hiding News is just a
/// preference the tab bar honors — no dead code paths.
final class TabVisibilityTests: XCTestCase {

    func testHomeShownWhenNewsEnabled() {
        let tabs = Tab.visible(showNews: true)
        XCTAssertEqual(tabs.first, .home)
        XCTAssertTrue(tabs.contains(.home))
        // The other tabs are always present.
        XCTAssertTrue(tabs.contains(.watchlist))
        XCTAssertTrue(tabs.contains(.portfolios))
        XCTAssertTrue(tabs.contains(.settings))
    }

    func testHomeHiddenWhenNewsDisabled() {
        let tabs = Tab.visible(showNews: false)
        XCTAssertFalse(tabs.contains(.home))
        // Watchlist becomes the leading tab.
        XCTAssertEqual(tabs.first, .watchlist)
        XCTAssertEqual(tabs, [.watchlist, .portfolios, .settings])
    }

    func testResolvingHiddenTabFallsBackToFirstVisible() {
        // A persisted "Home" selection must not strand the user on a hidden tab.
        XCTAssertEqual(Tab.resolve(stored: "Home", showNews: false), .watchlist)
        XCTAssertEqual(Tab.resolve(stored: "Home", showNews: true), .home)
        XCTAssertEqual(Tab.resolve(stored: "Portfolios", showNews: false), .portfolios)
        XCTAssertEqual(Tab.resolve(stored: "garbage", showNews: false), .watchlist)
    }
}
