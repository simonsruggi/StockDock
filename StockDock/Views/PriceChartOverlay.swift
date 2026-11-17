import SwiftUI
import Charts

/// Hover crosshair and drag-to-measure over `PriceChartPlot`. It owns the
/// pointer state, so moving the mouse redraws only this layer, never the marks.
///
/// Hover shows the close under the cursor; click-and-drag shades the span
/// between two dates and shows the change between them.
struct PriceChartOverlay: View {
    let proxy: ChartProxy
    let points: [PricePoint]
    let range: ChartRange
    let tint: Color
    let up: Color
    let down: Color
    let priceSymbol: String
    let priceDecimals: Int
    let percentDecimals: Int

    @State private var hoverPoint: PricePoint?
    @State private var measure: (start: PricePoint, end: PricePoint)?

    private func dateLabel(_ date: Date) -> String {
        range.isIntraday ? date.formatted(.dateTime.hour().minute())
                         : date.formatted(date: .abbreviated, time: .omitted)
    }

    private func price(_ value: Double) -> String {
        "\(priceSymbol)\(StorageService.formatNumber(value, decimals: priceDecimals))"
    }

    private func point(atX x: CGFloat, in plot: CGRect) -> PricePoint? {
        let localX = min(max(x - plot.minX, 0), plot.width)
        guard let date: Date = proxy.value(atX: localX) else { return nil }
        return nearestByDate(points, to: date, date: \.date)
    }

    private func screenX(_ point: PricePoint, in plot: CGRect) -> CGFloat? {
        proxy.position(forX: point.date).map { plot.minX + $0 }
    }

    var body: some View {
        GeometryReader { geo in
            if let plotAnchor = proxy.plotFrame {
                let plot = geo[plotAnchor]
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc): hoverPoint = point(atX: loc.x, in: plot)
                            case .ended: hoverPoint = nil
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { drag in
                                    guard let a = point(atX: drag.startLocation.x, in: plot),
                                          let b = point(atX: drag.location.x, in: plot) else { return }
                                    measure = a.date <= b.date ? (a, b) : (b, a)
                                }
                                .onEnded { _ in measure = nil }
                        )
                    // Decorations must not steal hover or the drag from the catcher.
                    Group {
                        if let m = measure { measureLayer(m, plot: plot) }
                        else if let h = hoverPoint { hoverLayer(h, plot: plot) }
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder private func hoverLayer(_ h: PricePoint, plot: CGRect) -> some View {
        if let cx = screenX(h, in: plot), let py = proxy.position(forY: h.close) {
            rule(at: cx, plot: plot)
            Circle().fill(tint).frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .position(x: cx, y: plot.minY + py)
            ChartTooltip(title: dateLabel(h.date), value: price(h.close), tint: tint)
                .position(x: min(max(cx, plot.minX + 50), plot.maxX - 50), y: plot.minY + 12)
        }
    }

    @ViewBuilder private func measureLayer(_ m: (start: PricePoint, end: PricePoint), plot: CGRect) -> some View {
        if let x0 = screenX(m.start, in: plot), let x1 = screenX(m.end, in: plot) {
            let change = m.end.close - m.start.close
            let pct = m.start.close != 0 ? change / m.start.close * 100 : 0
            let color = change >= 0 ? up : down
            Rectangle().fill(color.opacity(0.10))
                .frame(width: max(x1 - x0, 1), height: plot.height)
                .position(x: (x0 + x1) / 2, y: plot.midY)
            rule(at: x0, plot: plot)
            rule(at: x1, plot: plot)
            ChartTooltip(title: "\(dateLabel(m.start.date)) → \(dateLabel(m.end.date))",
                         value: String(format: "%+.\(percentDecimals)f%%", pct) + "  "
                             + StorageService.formatAmount(change, symbol: priceSymbol, signed: true),
                         tint: color)
                .position(x: min(max((x0 + x1) / 2, plot.minX + 80), plot.maxX - 80), y: plot.minY + 12)
        }
    }

    private func rule(at x: CGFloat, plot: CGRect) -> some View {
        Path { p in p.move(to: CGPoint(x: x, y: plot.minY)); p.addLine(to: CGPoint(x: x, y: plot.maxY)) }
            .stroke(DS.inkTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
    }
}
