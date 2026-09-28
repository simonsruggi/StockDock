import SwiftUI
import Charts

extension PortfolioOverviewView {
    // MARK: - Hero (chart as the ground of the card)

    func heroCard(_ d: Derived) -> some View {
        // Compute the (expensive) value series ONCE per render — it was being
        // recomputed 5× (badge, picker, chart points, chart dash), which showed
        // up as lag when switching portfolios (each switch rebuilds this view).
        let ds = displaySeries(totalValue: d.totalValue)
        // Pill reflects the SELECTED range: change across the drawn curve. When
        // the curve is too sparse to span a period (e.g. day one), fall back to
        // the day-over-day figure so the pill is never empty.
        //
        // 24H → the real "today" (extended-hours-aware day change), so the pill
        // matches the TODAY stat exactly and reflects the same price basis as the
        // value (incl. any pre/post-market move). All → the real all-time P&L, not
        // the reconstructed-curve span (which starts near €0 and reads a bogus
        // "+2202%"). 7D/1M/1Y → the curve span over that bounded window.
        let useRealDay = chartRange == .day
        let useRealAllTime = chartRange == .all
        let periodValue = useRealDay ? d.dayChangeValue
            : useRealAllTime ? d.totalPnl
            : (PortfolioPeriodChange.value(ds.points) ?? d.dayChangeValue)
        let periodPercent = useRealDay ? d.dayChangePercent
            : useRealAllTime ? d.totalPnlPercent
            : (PortfolioPeriodChange.percent(ds.points) ?? d.dayChangePercent)
        let periodLabel = useRealDay ? "today"
            : useRealAllTime ? "all-time"
            : (PortfolioPeriodChange.percent(ds.points) != nil ? chartRange.changeLabel : "today")
        // Header sits ABOVE the chart (not over it) so the curve can never rise
        // behind the value/pill text — on 24H the peak often lands top-left, right
        // where the text is, and no Y-domain trick can avoid that overlap.
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    SectionLabel("\(title) value")
                    Spacer()
                    HStack(spacing: 10) {
                        if ds.isEstimated, !ds.points.isEmpty {
                            Text("ESTIMATED")
                                .font(.inter(8.5, weight: .bold, relativeTo: .caption2)).tracking(0.8)
                                .foregroundStyle(DS.gold)
                                .help("Reconstructed from price history × current positions. Real daily tracking replaces it over time.")
                        }
                        // No picker over an empty chart — it appears with the data.
                        if !ds.points.isEmpty { rangePicker }
                    }
                }
                Text(StorageService.formatAmount(d.totalValue, symbol: currencySymbol, decimals: storageService.amountDecimals))
                    .font(DS.display).tracking(-0.5)
                    .foregroundStyle(DS.ink)
                    .contentTransition(.numericText())
                    // Price-driven: must settle between 1s tick flushes (see DS.tick).
                    .animation(DS.tick, value: d.totalValue)
                HStack(spacing: 10) {
                    ChangePill(value: periodValue,
                               text: String(format: "%+.\(decimals)f%% %@", periodPercent, periodLabel))
                    // The all-time figure alongside — hidden on the All range,
                    // where the pill already shows exactly this (no duplicate).
                    if !useRealAllTime {
                        Text(String(format: "%@ (%+.\(decimals)f%%) all-time",
                                    StorageService.formatAmount(d.totalPnl, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                                    d.totalPnlPercent))
                            .font(DS.caption.monospacedDigit())
                            .foregroundStyle(DS.pnlColor(d.totalPnl))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            heroChart(ds)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .premiumCard()
    }
    /// Smooth hover crosshair drawn as an overlay (not chart marks).
    @ViewBuilder private func valueCrosshair(_ proxy: ChartProxy, points: [ValuePoint], tint: Color) -> some View {
        GeometryReader { geo in
            if let plotAnchor = proxy.plotFrame {
                let plot = geo[plotAnchor]
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                // Clamp inside the plot so edges still resolve a value.
                                let localX = min(max(loc.x - plot.minX, 0), plot.width)
                                if let d: Date = proxy.value(atX: localX) {
                                    hoverPoint = nearestByDate(points, to: d, date: \.date)
                                }
                            case .ended:
                                hoverPoint = nil
                            }
                        }
                    if let h = hoverPoint,
                       let px = proxy.position(forX: h.date),
                       let py = proxy.position(forY: h.value) {
                        let cx = plot.minX + px
                        Group {
                            Path { p in p.move(to: CGPoint(x: cx, y: plot.minY)); p.addLine(to: CGPoint(x: cx, y: plot.maxY)) }
                                .stroke(DS.inkTertiary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            Circle().fill(tint).frame(width: 9, height: 9)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .position(x: cx, y: plot.minY + py)
                            ChartTooltip(title: tooltipDate(h.date),
                                         value: StorageService.formatAmount(h.value, symbol: currencySymbol, decimals: storageService.amountDecimals),
                                         tint: tint)
                                .position(x: min(max(cx, plot.minX + 46), plot.maxX - 46), y: plot.minY + 8)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    @ViewBuilder private func heroChart(_ ds: (points: [ValuePoint], isEstimated: Bool)) -> some View {
        let points = ds.points
        if points.count >= 2 {
            // Consistent color across periods: emerald when the period is up,
            // terracotta when down. Estimated state is shown by the dash only.
            let periodUp = (points.last?.value ?? 0) >= (points.first?.value ?? 0)
            let tint = periodUp ? DS.up : DS.down
            let span = (points.last?.date.timeIntervalSince(points.first?.date ?? .distantPast)) ?? 0
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Day", p.date), y: .value("Value", p.value))
                        .foregroundStyle(.linearGradient(colors: [tint.opacity(0.22), tint.opacity(0)],
                                                         startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                        .foregroundStyle(tint).lineStyle(.init(lineWidth: 2, dash: ds.isEstimated ? [4, 3] : []))
                        .interpolationMethod(.monotone)
                }
                if let last = points.last {
                    PointMark(x: .value("Day", last.date), y: .value("Value", last.value))
                        .symbolSize(50)
                        .foregroundStyle(tint)
                }
            }
            .chartYScale(domain: valueDomain(points))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(DS.chartGrid)
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(StorageService.formatAmount(d, symbol: currencySymbol, decimals: 0))
                                .font(DS.micro).foregroundStyle(DS.inkTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(DS.chartGrid)
                    if let d = value.as(Date.self) {
                        AxisValueLabel { Text(xAxisLabel(d, span: span)).font(DS.micro).foregroundStyle(DS.inkTertiary) }
                    }
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in valueCrosshair(proxy, points: points, tint: tint) }
            // Morph marks in place when async data lands (avoids a hard "pop" as
            // intraday/history loads after a range switch).
            //
            // Keyed on the point COUNT, not the array: on the 24H range the last
            // point is re-pinned to the live total every tick (see displaySeries),
            // so `value: points` re-ran a 0.4s animation of every mark once a
            // second — and compared the whole array on every render besides. The
            // count still changes exactly when new bars arrive, which is the case
            // this animation exists for.
            .animation(.easeInOut(duration: 0.4), value: points.count)
            // Range switch replaces the chart; crossfade it rather than cut.
            .id(chartRange)
            .transition(.opacity.animation(.easeInOut(duration: 0.4)))
        } else {
            ZStack {
                DS.cardAlt.opacity(0.6)
                DecorativeCurve()
                    .stroke(DS.hairline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .padding(.horizontal, 24)
                VStack(spacing: 4) {
                    Text("Value history builds up day by day")
                        .font(.inter(11, weight: .medium, relativeTo: .caption)).foregroundStyle(DS.inkSecondary)
                    Text("Your first trend appears tomorrow.")
                        .font(DS.micro).foregroundStyle(DS.inkTertiary)
                }
            }
        }
    }
}
