import Foundation

/// Pure, unit-testable decision logic that keeps StockDock's data feed alive.
///
/// Extracted from `AppDelegate`/`WebSocketService` so the recovery rules can be
/// tested without URLSession, Timers, or NSWorkspace notifications. It exists
/// because a long-running instance (19h+ across overnight sleep/wake) was seen
/// with ZERO network activity — the WebSocket had died and the REST poll had
/// gone silent — leaving quotes frozen until a manual restart.
enum ConnectionSupervisor {

    /// Default horizon after which an in-flight refresh is presumed finished.
    static let refreshStaleAfter: TimeInterval = 45

    /// Default horizon of WebSocket silence after which the socket is presumed dead.
    static let connectionStaleAfter: TimeInterval = 90

    /// Whether an in-flight refresh should block a new one.
    ///
    /// Previously this was a bare `Bool` flag: if the refresh `Task` was
    /// cancelled by a sleep/wake race and never ran its `defer` to reset the
    /// flag, it stuck at `true` and silently disabled *all* REST polling. By
    /// keying off the refresh *start time* instead, anything older than
    /// `staleAfter` is treated as finished, so polling always self-heals.
    static func refreshIsBlocking(startedAt: Date?, now: Date, staleAfter: TimeInterval = refreshStaleAfter) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) < staleAfter
    }

    /// Whether the WebSocket feed must be (re)connected.
    ///
    /// The feed is dead when it is not connected, or when it is nominally
    /// connected but no tick (nor the initial open) has been seen within
    /// `staleAfter`. This lets the periodic REST poll act as a supervisor that
    /// revives a socket which silently died across a sleep/wake cycle — even if
    /// no failure callback ever fired.
    ///
    /// When `reconnectPending` is true a backoff reconnect is already scheduled,
    /// so the supervisor stands down and lets the exponential backoff run its
    /// course — otherwise the 60s poll would keep resetting the backoff to zero
    /// and hammer a struggling endpoint every minute.
    static func shouldReconnect(isConnected: Bool, lastActivity: Date?, now: Date, reconnectPending: Bool = false, staleAfter: TimeInterval = connectionStaleAfter) -> Bool {
        if reconnectPending { return false }
        guard isConnected else { return true }
        guard let lastActivity else { return true }
        return now.timeIntervalSince(lastActivity) > staleAfter
    }
}
