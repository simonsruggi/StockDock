import SwiftUI
import Charts

extension PortfolioOverviewView {
    // MARK: - Stats

    func statRow(_ d: Derived) -> some View {
        HStack(spacing: 12) {
            StatTile(label: "Total P&L",
                     value: StorageService.formatAmount(d.totalPnl, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                     caption: String(format: "%+.\(decimals)f%% on cost", d.totalPnlPercent),
                     captionTint: DS.pnlColor(d.totalPnl), valueTint: DS.pnlColor(d.totalPnl),
                     help: "Total profit/loss vs your cost basis")
            StatTile(label: "Today",
                     value: StorageService.formatAmount(d.dayChangeValue, symbol: currencySymbol, decimals: storageService.amountDecimals, signed: true),
                     caption: String(format: "%+.\(decimals)f%%", d.dayChangePercent),
                     captionTint: DS.pnlColor(d.dayChangeValue), valueTint: DS.pnlColor(d.dayChangeValue),
                     help: "Change since the previous close")
            StatTile(label: "Invested",
                     value: StorageService.formatAmount(d.totalCost, symbol: currencySymbol, decimals: storageService.amountDecimals),
                     caption: "\(d.holdings.count) holdings",
                     help: "Total amount invested (cost basis)")
            StatTile(label: "Concentration",
                     value: String(format: "%.1f%%", d.topWeight),
                     caption: d.topSymbol.map { d.topWeight > 40 ? "high · top \($0)" : "top · \($0)" } ?? "—",
                     captionTint: d.topWeight > 40 ? DS.gold : DS.inkTertiary,
                     help: "Weight of your largest position — a diversification risk gauge")
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
                                .onHover { hoveredSlice = $0 ? slice.symbol : nil }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !d.typeBreakdown.isEmpty {
                        Divider().overlay(DS.hairline)
                        typeStrip(d)
                    }
                }
            }
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

    // MARK: - Movers

    func moversCard(proxy: ScrollViewProxy, _ d: Derived) -> some View {
        Card(title: "Today's movers") {
            var seen = Set<String>()
            let movers = d.holdings.filter { seen.insert($0.symbol).inserted }
                .sorted { abs($0.dayChangePercent) > abs($1.dayChangePercent) }
            let maxAbs = movers.map { abs($0.dayChangePercent) }.max() ?? 1
            if movers.isEmpty {
                emptyLine
            } else {
                VStack(spacing: 0) {
                    ForEach(movers.prefix(5)) { h in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DS.brand.opacity(0.10))
                                .frame(width: 24, height: 24)
                                .overlay(Text(h.symbol.prefix(1))
                                    .font(DS.micro).foregroundStyle(DS.brand))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.symbol).font(DS.figure).foregroundStyle(DS.ink)
                                Text(h.name).font(DS.micro).foregroundStyle(DS.inkTertiary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "%+.\(decimals)f%%", h.dayChangePercent))
                                    .font(.inter(12, weight: .semibold, relativeTo: .body).monospacedDigit())
                                    .foregroundStyle(DS.pnlColor(h.dayChangePercent))
                                ZStack(alignment: h.dayChangePercent >= 0 ? .leading : .trailing) {
                                    Capsule().fill(DS.cardAlt).frame(width: 48, height: 4)
                                    Capsule().fill(DS.pnlColor(h.dayChangePercent))
                                        .frame(width: max(4, 48 * abs(h.dayChangePercent) / max(maxAbs, 0.01)), height: 4)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        if h.id != movers.prefix(5).last?.id {
                            Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                        }
                    }
                    if d.holdings.count > 5 {
                        Button {
                            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("positions", anchor: .top) }
                        } label: {
                            Text("View all positions ↓")
                                .font(.inter(10.5, weight: .medium, relativeTo: .caption2))
                                .foregroundStyle(DS.brand)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                }
            }
        }
    }
}
