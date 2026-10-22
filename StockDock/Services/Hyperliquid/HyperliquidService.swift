import Foundation

/// Live 24/7 prices from Hyperliquid (trade.xyz perps): one REST snapshot for
/// the active coins, then a `bbo` WebSocket subscription per tracked coin.
/// Public API, no key.
@MainActor
final class HyperliquidService: ObservableObject {
    static let shared = HyperliquidService()

    /// coin ("xyz:AAPL") → mid price, USD.
    @Published private(set) var mids: [String: Double] = [:]

    private var activeCoins: Set<String> = []
    private var coins: [String] = []
    private var enabled = false
    private var task: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var snapshotTimer: Timer?
    private var flushTimer: Timer?
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private var pending: [String: Double] = [:]

    private static let infoURL = URL(string: "https://api.hyperliquid.xyz/info")!
    private static let wsURL = URL(string: "wss://api.hyperliquid.xyz/ws")!
    /// The server drops a socket idle for 60s.
    private static let pingInterval: TimeInterval = 30
    private static let snapshotInterval: TimeInterval = 300
    private static let flushInterval: TimeInterval = 2
    private static let maxReconnectDelay: TimeInterval = 120

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init() {}

    /// The 24/7 price for a quote, only off-hours (see `HyperliquidSymbols.isOffHours`).
    func quote(for q: StockQuote) -> AllHoursQuote? {
        guard enabled, HyperliquidSymbols.isOffHours(marketState: q.marketState, now: Date()),
              HyperliquidSymbols.accepts(symbol: q.symbol, currency: q.currency),
              let coin = HyperliquidSymbols.coin(for: q.symbol), activeCoins.contains(coin),
              let mid = mids[coin], HyperliquidSymbols.isPlausible(mid, reference: q.price) else { return nil }
        let change = mid - q.price
        return AllHoursQuote(coin: coin, price: mid, change: change, changePercent: change / q.price * 100)
    }

    /// Price a position is valued at: the 24/7 price off-hours, the usual (extended-hours aware) price otherwise.
    func livePrice(for q: StockQuote, extendedHours: Bool) -> Double {
        quote(for: q)?.price ?? q.displayPrice(extendedHours: extendedHours)
    }

    /// Today's change per share consistent with `livePrice`. In pre-market the
    /// regular close is the previous session's, so today's move is the 24/7 one alone.
    func liveChange(for q: StockQuote, extendedHours: Bool) -> Double {
        guard let a = quote(for: q) else { return q.effectiveChange(extendedHours: extendedHours) }
        return q.marketState == "PRE" ? a.change : q.change + a.change
    }

    /// Starts, resubscribes or stops the feed for the tracked symbols.
    func update(symbols: [String], enabled: Bool) {
        let wanted = Array(Set(symbols.compactMap(HyperliquidSymbols.coin(for:)))).sorted()
        guard enabled, !wanted.isEmpty else { stop(); return }
        let wasRunning = self.enabled
        self.enabled = true
        let changed = wanted != coins
        coins = wanted
        if !wasRunning {
            Task { await refreshSnapshot(); connect() }
            snapshotTimer = Timer.scheduledTimer(withTimeInterval: Self.snapshotInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshSnapshot()
                    self?.connect()
                }
            }
        } else if changed {
            Task {
                await refreshSnapshot()
                disconnectSocket()
                connect()
            }
        }
    }

    func stop() {
        enabled = false
        coins = []
        snapshotTimer?.invalidate(); snapshotTimer = nil
        disconnectSocket()
        objectWillChange.send()
    }

    // MARK: - REST snapshot

    private struct Meta: Decodable {
        struct Asset: Decodable { let name: String; let isDelisted: Bool? }
        let universe: [Asset]
    }
    private struct AssetCtx: Decodable { let midPx: String?; let markPx: String? }

    private func refreshSnapshot() async {
        var request = URLRequest(url: Self.infoURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "metaAndAssetCtxs", "dex": HyperliquidSymbols.dex])
        guard let (data, _) = try? await session.data(for: request),
              let parts = try? JSONSerialization.jsonObject(with: data) as? [Any], parts.count == 2,
              let metaData = try? JSONSerialization.data(withJSONObject: parts[0]),
              let ctxData = try? JSONSerialization.data(withJSONObject: parts[1]),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData),
              let ctxs = try? JSONDecoder().decode([AssetCtx].self, from: ctxData),
              meta.universe.count == ctxs.count, enabled else { return }

        var active = Set<String>()
        var snapshot = mids
        for (asset, ctx) in zip(meta.universe, ctxs) where asset.isDelisted != true {
            active.insert(asset.name)
            if coins.contains(asset.name), let px = Double(ctx.midPx ?? ctx.markPx ?? "") {
                snapshot[asset.name] = px
            }
        }
        activeCoins = active
        mids = snapshot
    }

    // MARK: - WebSocket

    /// Subscribes only to coins the snapshot lists: the server drops the whole
    /// socket on a subscription to an unknown coin, so one unlisted ticker would
    /// otherwise keep the feed reconnecting forever.
    private func connect() {
        let listed = coins.filter(activeCoins.contains)
        guard enabled, task == nil, reconnectTimer == nil, !listed.isEmpty else { return }
        let t = session.webSocketTask(with: Self.wsURL)
        task = t
        t.resume()
        for coin in listed {
            send(["method": "subscribe", "subscription": ["type": "bbo", "coin": coin]])
        }
        receive(on: t)
        pingTimer = Timer.scheduledTimer(withTimeInterval: Self.pingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.send(["method": "ping"]) }
        }
    }

    private func disconnectSocket() {
        pingTimer?.invalidate(); pingTimer = nil
        reconnectTimer?.invalidate(); reconnectTimer = nil
        flushTimer?.invalidate(); flushTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func receive(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(on: t)
                case .failure:
                    self.scheduleReconnect()
                }
            }
        }
    }

    private struct BBOMessage: Decodable {
        struct Level: Decodable { let px: String }
        struct Payload: Decodable { let coin: String; let bbo: [Level?] }
        let channel: String
        let data: Payload?
    }

    private func handle(_ text: String) {
        guard text.contains("\"bbo\""),
              let msg = try? JSONDecoder().decode(BBOMessage.self, from: Data(text.utf8)),
              msg.channel == "bbo", let payload = msg.data else { return }
        let sides = payload.bbo.compactMap { $0.flatMap { Double($0.px) } }
        guard !sides.isEmpty else { return }
        // Only real prices prove the socket healthy: the subscription ack
        // arrives even right before the server closes it.
        reconnectAttempts = 0
        pending[payload.coin] = sides.reduce(0, +) / Double(sides.count)
        scheduleFlush()
    }

    /// Coalesces book updates so views redraw at most every `flushInterval`.
    private func scheduleFlush() {
        guard flushTimer == nil else { return }
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.flushInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.flushTimer = nil
                guard !self.pending.isEmpty else { return }
                self.mids.merge(self.pending) { _, new in new }
                self.pending.removeAll()
            }
        }
    }

    private func scheduleReconnect() {
        disconnectSocket()
        guard enabled else { return }
        reconnectAttempts += 1
        let delay = min(pow(2, Double(reconnectAttempts)), Self.maxReconnectDelay)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.reconnectTimer = nil
                self?.connect()
            }
        }
    }
}
