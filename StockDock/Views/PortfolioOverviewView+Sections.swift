import SwiftUI
import Charts

extension PortfolioOverviewView {
    // MARK: - Stats

    func statRow(_ d: Derived, _ period: PeriodSummary) -> some View {
        HStack(spacing: 12) {
            StatTile(label: storageService.taxRate > 0 ? "Net P&L" : "Total P&L",
                     value: StorageService.formatAmount(d.totalPnl, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                     caption: String(format: "%+.\(decimals)f%% on cost", d.totalPnlPercent),
                     captionTint: DS.pnlColor(d.totalPnl), valueTint: DS.pnlColor(d.totalPnl),
                     help: "Total profit/loss vs your cost basis")
            // Follows the chart range; on All the first tile already is the
            // all-time figure, so this one stays on today.
            let showsRange = !period.isAllTime && period.tileLabel != "Today"
            let changeValue = showsRange ? period.value : d.dayChangeValue
            let changePercent = showsRange ? period.percent : d.dayChangePercent
            StatTile(label: showsRange ? period.tileLabel : "Today",
                     value: StorageService.formatAmount(changeValue, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                     caption: String(format: "%+.\(decimals)f%%", changePercent),
                     captionTint: DS.pnlColor(changeValue), valueTint: DS.pnlColor(changeValue),
                     help: showsRange ? "Change over the selected range, at today's share counts" : "Change since the previous close")
            StatTile(label: "Invested",
                     value: StorageService.formatAmount(d.totalCost, symbol: currencySymbol, decimals: storageService.amountDecimals),
                     caption: "\(d.holdings.count) holdings",
                     help: "Total amount invested (cost basis)")
            StatTile(label: "Concentration",
                     value: String(format: "%.1f%%", d.topWeight),
                     caption: d.topSymbol.map { d.topWeight > 40 ? "high · top \($0)" : "top · \($0)" } ?? "—",
                     captionTint: d.topWeight > 40 ? DS.gold : DS.inkTertiary,
                     help: "Share of your invested capital in your largest position")
        }
    }

    // MARK: - Allocation (donut + legend + type strip)
    func allocationCard(_ d: Derived) -> some View {
        Card(title: "Allocation") {
            if d.allocation.isEmpty {
                emptyLine
            } else {
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        ZStack {
                            Chart(d.allocation) { slice in
                                SectorMark(angle: .value("Value", slice.value),
                                           innerRadius: .ratio(0.64), angularInset: 2)
                                    .cornerRadius(3)
                                    .foregroundStyle(d.color(for: slice.symbol))
                                    .opacity(hoveredSlice == nil || hoveredSlice == slice.symbol ? 1 : 0.35)
                            }
                            .chartLegend(.hidden)
                            VStack(spacing: 1) {
                                Text("\(d.allocation.count)").font(DS.figureLG).foregroundStyle(DS.ink)
                                SectionLabel("Assets")
                            }
                        }
                        .frame(width: 136, height: 136)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let loc):
                                hoveredSlice = DonutHitTest.slice(
                                    at: loc, in: CGSize(width: 136, height: 136), innerRatio: 0.64,
                                    fractions: d.allocation.map { ($0.symbol, $0.fraction) })
                            case .ended:
                                hoveredSlice = nil
                            }
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(d.allocation.prefix(6)) { slice in
                                HStack(spacing: 9) {
                                    RoundedRectangle(cornerRadius: 2.5).fill(d.color(for: slice.symbol)).frame(width: 9, height: 9)
                                    Text(slice.symbol).font(DS.figure).foregroundStyle(DS.ink)
                                    Spacer()
                                    Text(String(format: "%.1f%%", slice.fraction * 100))
                                        .font(DS.figure).foregroundStyle(DS.inkSecondary)
                                }
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { hoveredSlice = slice.symbol }
                                    else if hoveredSlice == slice.symbol { hoveredSlice = nil }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !d.typeBreakdown.isEmpty {
                        Divider().overlay(DS.hairline)
                        typeStrip(d)
                    }
                }
                .onContinuousHover { phase in
                    if case .active(let loc) = phase { allocationHover = loc } else { allocationHover = nil }
                }
                .overlay { allocationTooltip(d) }
            }
        }
    }

    @ViewBuilder private func allocationTooltip(_ d: Derived) -> some View {
        if let symbol = hoveredSlice, let loc = allocationHover,
           let slice = d.allocation.first(where: { $0.symbol == symbol }) {
            GeometryReader { geo in
                let toLeft = loc.x + 16 + AllocationTooltip.width > geo.size.width
                let above = loc.y > geo.size.height / 2
                ZStack(alignment: .topLeading) {
                    Color.clear
                    AllocationTooltip(symbol: symbol,
                                      holdings: d.holdings.filter { $0.symbol == symbol },
                                      weight: slice.fraction * 100,
                                      tint: d.color(for: symbol),
                                      currencySymbol: currencySymbol,
                                      amountDecimals: storageService.amountDecimals,
                                      percentDecimals: decimals,
                                      taxRate: d.taxRate)
                        .alignmentGuide(.leading) { toLeft ? $0.width - (loc.x - 16) : -(loc.x + 16) }
                        .alignmentGuide(.top) { above ? $0.height - (loc.y - 12) : -(loc.y + 16) }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func typeStrip(_ d: Derived) -> some View {
        let typeBreakdown = d.typeBreakdown
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(typeBreakdown.enumerated()), id: \.element.label) { idx, row in
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(DS.palette[idx % DS.palette.count])
                            .frame(width: max(2, geo.size.width * row.fraction - 2))
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                ForEach(Array(typeBreakdown.enumerated()), id: \.element.label) { idx, row in
                    HStack(spacing: 5) {
                        Circle().fill(DS.palette[idx % DS.palette.count]).frame(width: 6, height: 6)
                        Text(row.label).font(DS.caption).foregroundStyle(DS.inkSecondary)
                        Text(String(format: "%.0f%%", row.fraction * 100))
                            .font(DS.caption.monospacedDigit()).foregroundStyle(DS.inkTertiary)
                    }
                }
                Spacer()
            }
        }
    }
}
