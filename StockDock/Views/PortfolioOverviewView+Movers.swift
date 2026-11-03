import SwiftUI

extension PortfolioOverviewView {
    /// The selected range's change, shared by the hero pill, the change tile and
    /// the movers card so the three always tell the same story.
    struct PeriodSummary {
        let value: Double
        let percent: Double
        /// Suffix for the hero pill ("today", "past 7d", "all-time").
        let label: String
        /// Tile title: "Today" or "Past 7D" / "Past 1M" / "Past 1Y".
        let tileLabel: String
        let moversTitle: String
        let moves: [PeriodMove]
        var isAllTime: Bool { label == "all-time" }
    }

    func periodSummary(_ d: Derived, _ ds: (points: [ValuePoint], isEstimated: Bool)) -> PeriodSummary {
        let extended = storageService.showExtendedHours
        let live = HyperliquidService.shared
        switch chartRange {
        case .day:
            return PeriodSummary(value: d.dayChangeValue, percent: d.dayChangePercent, label: "today",
                                 tileLabel: "Today", moversTitle: "Today's movers", moves: dayMoves(d))
        case .all:
            return PeriodSummary(value: d.totalPnl, percent: d.totalPnlPercent, label: "all-time",
                                 tileLabel: "Today", moversTitle: "All-time movers", moves: allTimeMoves(d))
        case .week, .month, .year:
            let days = chartRange.days ?? 7
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let history = chartRange == .week ? stockService.intradayWeek : stockService.priceHistory
            let moves = PeriodMovers.moves(holdings: d.holdings, history: history, since: cutoff,
                                           livePrice: { live.livePrice(for: $0, extendedHours: extended) },
                                           rate: { stockService.rate(from: $0) })
            let title = "Movers · \(chartRange.rawValue)"
            let tile = "Past \(chartRange.rawValue)"
            if let total = PeriodMovers.total(moves) {
                return PeriodSummary(value: total.value, percent: total.percent, label: chartRange.changeLabel,
                                     tileLabel: tile, moversTitle: title, moves: moves)
            }
            // No history yet for any symbol: the curve, or today as a last resort.
            if let v = PortfolioPeriodChange.value(ds.points), let p = PortfolioPeriodChange.percent(ds.points) {
                return PeriodSummary(value: v, percent: p, label: chartRange.changeLabel,
                                     tileLabel: tile, moversTitle: title, moves: [])
            }
            return PeriodSummary(value: d.dayChangeValue, percent: d.dayChangePercent, label: "today",
                                 tileLabel: "Today", moversTitle: "Today's movers", moves: dayMoves(d))
        }
    }

    private func dayMoves(_ d: Derived) -> [PeriodMove] {
        let extended = storageService.showExtendedHours
        let live = HyperliquidService.shared
        var value: [String: Double] = [:], base: [String: Double] = [:], names: [String: String] = [:]
        for h in d.holdings {
            let fx = stockService.rate(from: h.quote.currency)
            let change = live.liveChange(for: h.quote, extendedHours: extended)
            let price = live.livePrice(for: h.quote, extendedHours: extended)
            let exposure = h.holding.quantity * h.holding.effectiveLeverage
            value[h.symbol, default: 0] += h.holding.dailyPnl(priceChange: change) * fx
            base[h.symbol, default: 0] += abs((price - change) * exposure * fx)
            names[h.symbol] = h.name
        }
        return value.map { PeriodMove(symbol: $0.key, name: names[$0.key] ?? $0.key, value: $0.value, base: base[$0.key] ?? 0) }
            .sorted { abs($0.value) > abs($1.value) }
    }

    private func allTimeMoves(_ d: Derived) -> [PeriodMove] {
        var value: [String: Double] = [:], base: [String: Double] = [:], names: [String: String] = [:]
        for h in d.holdings {
            value[h.symbol, default: 0] += CapitalGainsTax.net(h.pnl, ratePercent: d.taxRate)
            base[h.symbol, default: 0] += abs(h.cost)
            names[h.symbol] = h.name
        }
        return value.map { PeriodMove(symbol: $0.key, name: names[$0.key] ?? $0.key, value: $0.value, base: base[$0.key] ?? 0) }
            .sorted { abs($0.value) > abs($1.value) }
    }

    // MARK: - Movers

    func moversCard(proxy: ScrollViewProxy, _ d: Derived, _ period: PeriodSummary) -> some View {
        Card(title: period.moversTitle) {
            let movers = Array(period.moves.prefix(5))
            let maxAbs = movers.map { abs($0.percent) }.max() ?? 1
            if movers.isEmpty {
                emptyLine
            } else {
                VStack(spacing: 0) {
                    ForEach(movers) { m in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DS.brand.opacity(0.10))
                                .frame(width: 24, height: 24)
                                .overlay(Text(m.symbol.prefix(1))
                                    .font(DS.micro).foregroundStyle(DS.brand))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.symbol).font(DS.figure).foregroundStyle(DS.ink)
                                Text(StorageService.formatAmount(m.value, symbol: currencySymbol,
                                                                 decimals: storageService.amountDecimals, signed: true))
                                    .font(DS.micro.monospacedDigit()).foregroundStyle(DS.pnlColor(m.value))
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(String(format: "%+.\(decimals)f%%", m.percent))
                                    .font(.inter(12, weight: .semibold, relativeTo: .body).monospacedDigit())
                                    .foregroundStyle(DS.pnlColor(m.value))
                                ZStack(alignment: m.percent >= 0 ? .leading : .trailing) {
                                    Capsule().fill(DS.cardAlt).frame(width: 48, height: 4)
                                    Capsule().fill(DS.pnlColor(m.value))
                                        .frame(width: max(4, 48 * abs(m.percent) / max(maxAbs, 0.01)), height: 4)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .help(m.name)
                        if m.id != movers.last?.id {
                            Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                        }
                    }
                    if period.moves.count > 5 {
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
