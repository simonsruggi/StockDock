import SwiftUI
import Charts

/// The price line of `PriceChartCard`. Takes plain values and is compared with
/// `.equatable()`, so the live-price tick that redraws the card header every
/// second does not rebuild a few hundred chart marks: the plot redraws only
/// when its series, range or colors change.
struct PriceChartPlot: View, Equatable {
    let points: [PricePoint]
    let range: ChartRange
    let up: Color
    let down: Color
    let priceSymbol: String
    let priceDecimals: Int
    let percentDecimals: Int
    /// The holding's average purchase price, drawn as a dashed line when it falls
    /// near the plotted prices.
    let costBasis: Double?

    static func == (a: Self, b: Self) -> Bool {
        a.range == b.range && a.points.count == b.points.count
            && a.points.first == b.points.first && a.points.last == b.points.last
            && a.up == b.up && a.down == b.down && a.costBasis == b.costBasis
            && a.priceSymbol == b.priceSymbol && a.priceDecimals == b.priceDecimals
            && a.percentDecimals == b.percentDecimals
    }

    private var tint: Color {
        (points.last?.close ?? 0) >= (points.first?.close ?? 0) ? up : down
    }

    /// The cost line is shown only when it sits within one price span of the
    /// series: further away it would squash a short range into a flat line.
    private var visibleCost: Double? {
        guard let cost = costBasis, cost > 0,
              let lo = points.map(\.close).min(), let hi = points.map(\.close).max() else { return nil }
        let span = max(hi - lo, hi * 0.01)
        return (lo - span)...(hi + span) ~= cost ? cost : nil
    }

    private var domain: ClosedRange<Double> {
        var closes = points.map(\.close)
        if let cost = visibleCost { closes.append(cost) }
        guard let lo = closes.min(), let hi = closes.max(), hi > lo else { return 0...1 }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    private func xAxisLabel(_ date: Date) -> String {
        switch range {
        case .day: return date.formatted(.dateTime.hour().minute())
        case .week: return date.formatted(.dateTime.weekday(.abbreviated))
        default:
            return range.isShortSpan ? date.formatted(.dateTime.day().month(.abbreviated))
                                     : date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    var body: some View {
        let tint = tint
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Day", point.date), y: .value("Close", point.close))
                    .foregroundStyle(.linearGradient(colors: [tint.opacity(0.25), tint.opacity(0)],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Day", point.date), y: .value("Close", point.close))
                    .foregroundStyle(tint).lineStyle(.init(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            if let cost = visibleCost {
                RuleMark(y: .value("Avg price", cost))
                    .foregroundStyle(DS.inkTertiary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("Avg \(priceSymbol)\(StorageService.formatNumber(cost, decimals: priceDecimals))")
                            .font(DS.micro).foregroundStyle(DS.inkTertiary)
                    }
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.date), y: .value("Close", last.close))
                    .symbolSize(50)
                    .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(DS.chartGrid)
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(StorageService.formatNumber(d, decimals: d >= 100 ? 0 : 2))
                            .font(DS.micro).foregroundStyle(DS.inkTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(DS.chartGrid)
                if let d = value.as(Date.self) {
                    AxisValueLabel { Text(xAxisLabel(d)).font(DS.micro).foregroundStyle(DS.inkTertiary) }
                }
            }
        }
        .chartOverlay { proxy in
            PriceChartOverlay(proxy: proxy, points: points, range: range, tint: tint, up: up, down: down,
                              priceSymbol: priceSymbol, priceDecimals: priceDecimals,
                              percentDecimals: percentDecimals)
        }
    }
}
