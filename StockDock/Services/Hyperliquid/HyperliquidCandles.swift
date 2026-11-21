import Foundation

/// 24/7 price history from Hyperliquid (`candleSnapshot`), used to fill the
/// hours Yahoo has no bars for (overnight, weekends, holidays) on the 24H and
/// 7D charts when "Overnight & weekends" is on. Public API, no key.
@MainActor
final class HyperliquidCandles: ObservableObject {
    static let shared = HyperliquidCandles()

    enum Span: String {
        case day, week

        var interval: String { self == .day ? "5m" : "1h" }
        /// Day reaches back past a weekend so Monday morning still links to Friday's session.
        var lookback: TimeInterval { self == .day ? 4 * 86400 : 8 * 86400 }
        var cacheSeconds: TimeInterval { self == .day ? 300 : 900 }
        /// A candle fills in only where Yahoo has no bar this close to it.
        var gap: TimeInterval { self == .day ? 600 : 5400 }
        /// Window drawn when Yahoo returned nothing at all.
        var fallbackWindow: TimeInterval { self == .day ? 86400 : 7 * 86400 }
    }

    struct Key: Hashable { let coin: String; let span: Span }

    @Published private(set) var candles: [Key: [PricePoint]] = [:]
    private var fetchedAt: [Key: Date] = [:]

    private static let infoURL = URL(string: "https://api.hyperliquid.xyz/info")!

    private init() {}

    func ensure(coin: String, span: Span) async {
        let key = Key(coin: coin, span: span)
        if let at = fetchedAt[key], Date().timeIntervalSince(at) < span.cacheSeconds { return }
        let now = Date()
        let body: [String: Any] = [
            "type": "candleSnapshot",
            "req": ["coin": coin, "interval": span.interval,
                    "startTime": Int(now.addingTimeInterval(-span.lookback).timeIntervalSince1970 * 1000),
                    "endTime": Int(now.timeIntervalSince1970 * 1000)],
        ]
        var request = URLRequest(url: Self.infoURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let points = Self.points(from: data) else { return }
        candles[key] = points
        fetchedAt[key] = now
    }

    func ensure(coins: [String], span: Span) async {
        await withTaskGroup(of: Void.self) { group in
            for coin in coins { group.addTask { await self.ensure(coin: coin, span: span) } }
        }
    }

    func points(coin: String, span: Span) -> [PricePoint]? {
        candles[Key(coin: coin, span: span)]
    }

    private struct Candle: Decodable { let t: Double; let c: String }

    nonisolated static func points(from data: Data) -> [PricePoint]? {
        guard let raw = try? JSONDecoder().decode([Candle].self, from: data) else { return nil }
        return raw.compactMap { candle in
            Double(candle.c).map { PricePoint(date: Date(timeIntervalSince1970: candle.t / 1000), close: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    /// Yahoo's bars with the candles slotted into the holes between (and after)
    /// them. Yahoo stays authoritative wherever it printed; candles outside the
    /// plausibility band of `reference` are dropped like the live 24/7 price is.
    nonisolated static func filling(_ yahoo: [PricePoint], with candles: [PricePoint], span: Span,
                                    reference: Double, now: Date = Date()) -> [PricePoint] {
        guard !candles.isEmpty else { return yahoo }
        let since = yahoo.first?.date ?? now.addingTimeInterval(-span.fallbackWindow)
        let yahooDates = yahoo.map(\.date)
        let extra = candles.filter { candle in
            candle.date >= since
                && HyperliquidSymbols.isPlausible(candle.close, reference: reference)
                && !hasBar(near: candle.date, in: yahooDates, within: span.gap)
        }
        guard !extra.isEmpty else { return yahoo }
        return (yahoo + extra).sorted { $0.date < $1.date }
    }

    /// Binary search over sorted dates for one within `tolerance` of `date`.
    private nonisolated static func hasBar(near date: Date, in sorted: [Date], within tolerance: TimeInterval) -> Bool {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < date { lo = mid + 1 } else { hi = mid }
        }
        if lo < sorted.count, sorted[lo].timeIntervalSince(date) <= tolerance { return true }
        if lo > 0, date.timeIntervalSince(sorted[lo - 1]) <= tolerance { return true }
        return false
    }
}
