import XCTest
@testable import StockDock

/// Reproduces the "prices frozen after a long uptime / overnight sleep-wake"
/// bug: the running app stopped all network activity (no WebSocket, no REST
/// poll) because (1) the `isRefreshing` guard got stuck `true` and silently
/// disabled polling, and (2) a WebSocket that died on wake was never revived.
/// These tests pin the pure recovery rules that now heal both cases.
final class ConnectionSupervisorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Stuck refresh guard

    /// A refresh flag left set long ago (e.g. its Task was cancelled by a
    /// sleep/wake race and never cleared the Bool) must NOT keep blocking the
    /// REST poll forever — otherwise quotes freeze until the app restarts.
    func testStaleRefreshDoesNotBlock() {
        let now = t0.addingTimeInterval(120) // 2 minutes after it started
        XCTAssertFalse(ConnectionSupervisor.refreshIsBlocking(startedAt: t0, now: now))
    }

    /// A refresh that genuinely just started still de-dupes concurrent refreshes.
    func testRecentRefreshBlocks() {
        let now = t0.addingTimeInterval(5)
        XCTAssertTrue(ConnectionSupervisor.refreshIsBlocking(startedAt: t0, now: now))
    }

    /// No refresh in flight never blocks.
    func testNoRefreshNeverBlocks() {
        XCTAssertFalse(ConnectionSupervisor.refreshIsBlocking(startedAt: nil, now: t0))
    }

    /// Exactly at the staleness horizon it is considered finished (not blocking).
    func testRefreshAtHorizonIsNotBlocking() {
        let now = t0.addingTimeInterval(45)
        XCTAssertFalse(ConnectionSupervisor.refreshIsBlocking(startedAt: t0, now: now, staleAfter: 45))
    }

    // MARK: - Dead-socket detection

    /// Not connected → the 60s supervisor must force a reconnect.
    func testDisconnectedNeedsReconnect() {
        XCTAssertTrue(ConnectionSupervisor.shouldReconnect(isConnected: false, lastActivity: t0, now: t0))
    }

    /// Connected but no tick nor open seen for a long time — the socket died
    /// silently across sleep/wake without any failure callback → reconnect.
    func testStaleConnectionNeedsReconnect() {
        let now = t0.addingTimeInterval(300)
        XCTAssertTrue(ConnectionSupervisor.shouldReconnect(isConnected: true, lastActivity: t0, now: now))
    }

    /// Connected and recently active → leave it alone (no churn).
    func testHealthyConnectionStaysConnected() {
        let now = t0.addingTimeInterval(10)
        XCTAssertFalse(ConnectionSupervisor.shouldReconnect(isConnected: true, lastActivity: t0, now: now))
    }

    /// Marked connected but never any activity recorded → treat as dead.
    func testConnectedButNoActivityYetReconnects() {
        XCTAssertTrue(ConnectionSupervisor.shouldReconnect(isConnected: true, lastActivity: nil, now: t0))
    }

    /// A backoff reconnect is already scheduled → the supervisor must stand down
    /// so the 60s poll can't keep resetting the exponential backoff to zero and
    /// hammer a struggling endpoint every minute.
    func testPendingReconnectSuppressesSupervisor() {
        XCTAssertFalse(ConnectionSupervisor.shouldReconnect(
            isConnected: false, lastActivity: nil, now: t0, reconnectPending: true))
    }

    /// With no reconnect pending, a disconnected feed still reconnects.
    func testNoPendingReconnectStillReconnects() {
        XCTAssertTrue(ConnectionSupervisor.shouldReconnect(
            isConnected: false, lastActivity: nil, now: t0, reconnectPending: false))
    }
}
