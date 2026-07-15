import Foundation
import SwiftProtobuf

@MainActor
final class WebSocketService: NSObject, ObservableObject {
    static let shared = WebSocketService()

    @Published var isConnected = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var heartbeatTimer: Timer?
    private var watchdogTimer: Timer?
    private var connectWatchdogTimer: Timer?
    private var lastTickTime: Date?
    private var subscribedSymbols: [String] = []
    private var reconnectAttempts = 0
    private var reconnectTimer: Timer?

    private static let watchdogInterval: TimeInterval = 30
    private static let watchdogTimeout: TimeInterval = 60
    /// If the socket doesn't open within this window, treat it as a silent
    /// failure and reconnect. Guards against a connection that fails *before*
    /// `didOpenWithProtocol` fires (common right after wake), which otherwise
    /// leaves the service stuck with no tick and no failure callback.
    private static let connectTimeout: TimeInterval = 12

    /// Last time the socket showed life (opened or received a tick). Used by
    /// `ConnectionSupervisor.shouldReconnect` to detect a silently dead socket.
    var lastActivity: Date? { lastTickTime }

    /// Called on main actor whenever a new tick arrives
    var onTick: ((Yaticker) -> Void)?

    private static let endpoint = URL(string: "wss://streamer.finance.yahoo.com/?version=2")!
    private static let heartbeatInterval: TimeInterval = 15
    private static let maxReconnectDelay: TimeInterval = 120

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func connect(symbols: [String]) {
        guard !symbols.isEmpty else { return }
        subscribedSymbols = symbols
        reconnectAttempts = 0
        openConnection()
    }

    /// Supervisor entry point (called from the periodic REST poll). Keeps the
    /// subscription list current and force-reconnects when the feed looks dead,
    /// so a socket that silently died across sleep/wake is revived within one
    /// poll interval instead of staying frozen until an app restart.
    func ensureConnected(symbols: [String]) {
        subscribedSymbols = symbols
        guard !symbols.isEmpty else { return }
        if ConnectionSupervisor.shouldReconnect(isConnected: isConnected, lastActivity: lastTickTime, now: Date(), reconnectPending: reconnectTimer != nil) {
            reconnectAttempts = 0
            openConnection()
        } else {
            updateSymbols(symbols)
        }
    }

    func updateSymbols(_ symbols: [String]) {
        let oldSet = Set(subscribedSymbols)
        let newSet = Set(symbols)
        subscribedSymbols = symbols

        guard isConnected, webSocketTask != nil else {
            // Not connected yet — symbols will be sent on connect
            return
        }

        let toUnsub = oldSet.subtracting(newSet)
        let toSub = newSet.subtracting(oldSet)

        if !toUnsub.isEmpty {
            sendJSON(["unsubscribe": Array(toUnsub)])
        }
        if !toSub.isEmpty {
            sendJSON(["subscribe": Array(toSub)])
        }
    }

    func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        connectWatchdogTimer?.invalidate()
        connectWatchdogTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        lastTickTime = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    // MARK: - Connection

    private func openConnection() {
        disconnect()

        let task = urlSession.webSocketTask(with: Self.endpoint)
        webSocketTask = task
        task.resume()
        // Subscribe + receive will start in didOpenWithProtocol delegate.
        // Arm a watchdog in case the socket never opens (silent pre-open failure).
        connectWatchdogTimer?.invalidate()
        connectWatchdogTimer = Timer.scheduledTimer(withTimeInterval: Self.connectTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isConnected else { return }
                self.handleDisconnect()
            }
        }
    }

    // MARK: - Messaging

    private func sendJSON(_ dict: [String: [String]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(str)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                self?.handleDisconnect()
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessage() // keep listening
                case .failure:
                    self.handleDisconnect()
                }
            }
        }
    }

    private struct WSSMessage: Decodable {
        let type: String?
        let message: String? // base64-encoded protobuf
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let t): text = t
        case .data(let d):
            guard let t = String(data: d, encoding: .utf8) else { return }
            text = t
        @unknown default: return
        }

        // Yahoo WSS v2 wraps protobuf in JSON: {"type":"pricing","message":"<base64>"}
        guard let jsonData = text.data(using: .utf8),
              let wssMsg = try? JSONDecoder().decode(WSSMessage.self, from: jsonData),
              let b64 = wssMsg.message,
              let protoData = Data(base64Encoded: b64)
        else {
            // Try direct base64 as fallback
            if let directData = Data(base64Encoded: text),
               let ticker = try? Yaticker(serializedBytes: directData),
               ticker.quoteType != .heartbeat {
                lastTickTime = Date()
                onTick?(ticker)
            }
            return
        }

        guard let ticker = try? Yaticker(serializedBytes: protoData) else { return }
        if ticker.quoteType == .heartbeat { return }

        lastTickTime = Date()
        onTick?(ticker)
    }


    // MARK: - Heartbeat & Watchdog

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.subscribedSymbols.isEmpty else { return }
                self.sendJSON(["subscribe": self.subscribedSymbols])
            }
        }
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        lastTickTime = Date()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isConnected else { return }
                guard let last = self.lastTickTime else { return }
                if Date().timeIntervalSince(last) > Self.watchdogTimeout {
                    self.handleDisconnect()
                }
            }
        }
    }

    // MARK: - Reconnect

    private func handleDisconnect() {
        isConnected = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connectWatchdogTimer?.invalidate()
        connectWatchdogTimer = nil

        // Abandon the current task so any late delegate callback for this
        // generation (didClose / didCompleteWithError / a slow didOpen) fails
        // its `task === webSocketTask` identity check and can't run
        // handleDisconnect twice (which would double-count reconnectAttempts and
        // skew the backoff) or resurrect a stale socket.
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        guard !subscribedSymbols.isEmpty else { return }

        let delay = min(pow(2.0, Double(reconnectAttempts)) * 2, Self.maxReconnectDelay)
        reconnectAttempts += 1

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.reconnectTimer = nil
                self?.openConnection()
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            // Ignore a stale open (e.g. a slow connect the watchdog already gave
            // up on) so it can't resurrect a socket we've moved on from.
            guard webSocketTask === self.webSocketTask else { return }
            self.connectWatchdogTimer?.invalidate()
            self.connectWatchdogTimer = nil
            self.isConnected = true
            self.reconnectAttempts = 0
            self.lastTickTime = Date() // count "opened" as activity until first tick
            self.sendJSON(["subscribe": self.subscribedSymbols])
            self.startHeartbeat()
            self.startWatchdog()
            self.receiveMessage()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            guard webSocketTask === self.webSocketTask else { return }
            self.handleDisconnect()
        }
    }

    /// Catches a socket that fails *before* (or without) opening — e.g. a
    /// connection attempt right after wake when the network isn't ready yet.
    /// Without this, `didOpenWithProtocol` never fires, nothing calls `receive`,
    /// and the failure would go unnoticed with no reconnect. Guarded by task
    /// identity so an intentionally-cancelled old socket can't trigger a loop.
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            guard error != nil, task === self.webSocketTask else { return }
            self.handleDisconnect()
        }
    }
}
