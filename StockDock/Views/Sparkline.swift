import SwiftUI
import Charts

/// A tiny 30-day price line for table rows — no axes, tinted by direction.
/// Lazily triggers the (cached) history fetch for its symbol.
///
/// Reads the shared service directly (not @EnvironmentObject): `Table` cells on
/// macOS are hosted outside the SwiftUI environment chain, so an environment
/// object would crash here.
struct Sparkline: View {
    @ObservedObject private var stockService = StockService.shared
    let symbol: String

    private var points: [PricePoint] {
        guard let all = stockService.priceHistory[symbol],
              let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        else { return [] }
        return all.filter { $0.date >= cutoff }
    }

    var body: some View {
        Group {
            if points.count >= 2 {
                let up = (points.last?.close ?? 0) >= (points.first?.close ?? 0)
                let tint = up ? DS.up : DS.down
                Chart(points) { point in
                    LineMark(x: .value("Day", point.date), y: .value("Close", point.close))
                        .foregroundStyle(tint).lineStyle(.init(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: sparkDomain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
            } else {
                Capsule().fill(DS.cardAlt).frame(height: 2)
            }
        }
        .frame(width: 64, height: 22)
        // History is filled by the watchlist's batched spark request, so no
        // per-row fetch here (that would be one request per symbol).
    }

    private var sparkDomain: ClosedRange<Double> {
        let closes = points.map(\.close)
        guard let min = closes.min(), let max = closes.max(), max > min else { return 0...1 }
        return min...max
    }
}
