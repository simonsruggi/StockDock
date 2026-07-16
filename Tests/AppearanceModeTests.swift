import XCTest
import SwiftUI
@testable import StockDock

/// Issue #11: the 1.9.0 redesign hard-forced the light appearance and dropped the
/// dark-mode toggle. These pin down the mapping that restores user control:
/// System follows the OS (nil scheme), Light/Dark force their scheme, and any
/// unknown persisted value falls back to System.
final class AppearanceModeTests: XCTestCase {

    func testSystemFollowsOS() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
    }

    func testLightForcesLight() {
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
    }

    func testDarkForcesDark() {
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }

    func testUnknownRawValueFallsBackToSystem() {
        XCTAssertEqual(AppearanceMode(rawValue: "chartreuse") ?? .system, .system)
        XCTAssertNil((AppearanceMode(rawValue: "chartreuse") ?? .system).colorScheme)
    }

    func testDefaultIsLight() {
        // The shipped default must not change the look for users happy with 1.9.x:
        // stay light by default, but let anyone opt into System or Dark.
        XCTAssertEqual(AppearanceMode.default, .light)
    }
}
