import SwiftUI
import Charts

/// A tiny price line for watchlist rows over the selected chart range, plus the
/// period's % change. No axes, tinted by direction.
///
/// Reads the shared services directly (not @EnvironmentObject): `Table` cells on
/// macOS are hosted outside the SwiftUI environment chain, so an environment
/// object would crash here.
struct Sparkline: View {
    @ObservedObject private var stockService = StockService.shared
    let symbol: String
    var range: SymbolChartRange = .month

    static let chartWidth: CGFloat = 80
    static let changeWidth: CGFloat = 50

    private var points: [PricePoint] { stockService.sparkSeries[range]?[symbol] ?? [] }

    /// First-to-last change over the period; nil without enough data.
    private var change: Double? {
        guard points.count >= 2, let first = points.first?.close, first > 0,
              let last = points.last?.close else { return nil }
        return (last / first - 1) * 100
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if points.count >= 2 {
                    let tint = (change ?? 0) >= 0 ? DS.up : DS.down
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
            .frame(width: Self.chartWidth, height: 22)

            // 24H's change is already the Price column's daily %, so leave it out.
            Group {
                if range != .day, let change {
                    // "All" can reach six-digit gains; decimals add nothing there.
                    let decimals = abs(change) >= 100 ? 0 : StorageService.shared.percentDecimals
                    Text(String(format: "%+.\(decimals)f%%", change))
                        .font(.inter(11, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(change >= 0 ? DS.up : DS.down)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.changeWidth, alignment: .trailing)
        }
        // History is filled by the watchlist's batched spark request, so no
        // per-row fetch here (that would be one request per symbol).
    }

    private var sparkDomain: ClosedRange<Double> {
        let closes = points.map(\.close)
        guard let min = closes.min(), let max = closes.max() else { return 0...1 }
        // A flat series still needs a band around it, or the line falls outside the domain.
        guard max > min else { return (min * 0.99)...(max * 1.01 + .ulpOfOne) }
        return min...max
    }
}
