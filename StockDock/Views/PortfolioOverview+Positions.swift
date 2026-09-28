import SwiftUI

extension PortfolioOverview {
    // MARK: - Positions

    func positionsCard(_ d: Derived) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionLabel("Positions")
                Spacer()
                addHoldingButton
            }
            if d.holdings.isEmpty {
                VStack(spacing: 10) {
                    Text("No holdings yet").font(DS.bodyStrong).foregroundStyle(DS.ink)
                    Text("Add your first position to start tracking value and P&L.")
                        .font(DS.caption).foregroundStyle(DS.inkSecondary)
                    addHoldingButton
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Symbol").frame(width: 168, alignment: .leading)
                        Text("Last").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Change").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Value").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("P&L").frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Weight").frame(width: 110, alignment: .trailing)
                        Color.clear.frame(width: 16)
                    }
                    .font(DS.label)
                    .foregroundStyle(DS.inkTertiary)
                    .tracking(0.8).textCase(.uppercase)
                    .padding(.bottom, 12)
                    Divider().overlay(DS.hairline)
                    ForEach(d.holdings) { h in
                        NavigationLink(value: h.id) {
                            PositionRow(h: h, currencySymbol: currencySymbol,
                                        weight: abs(d.totalValue) >= 0.01 ? abs(h.value) / abs(d.totalValue) * 100 : 0,
                                        topWeight: d.topWeight,
                                        decimals: decimals,
                                        valueDecimals: storageService.valueDecimals,
                                        percentDecimals: storageService.percentDecimals)
                        }
                        .buttonStyle(.plain)
                        .help("View \(h.symbol) details · right-click to edit or delete")
                        .contextMenu {
                            Button { editHoldingAction.perform(h.portfolioId, h.holding) } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) {
                                storageService.removeHolding(from: h.portfolioId, holdingId: h.holding.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                        if h.id != d.holdings.last?.id {
                            Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let h = d.holdings.first(where: { $0.id == id }) {
                        HoldingDetailView(portfolioId: h.portfolioId, holding: h.holding, quote: h.quote,
                                          value: h.value, cost: h.cost,
                                          weight: abs(d.totalValue) >= 0.01 ? abs(h.value) / abs(d.totalValue) * 100 : 0)
                    }
                }
            }
        }
        .padding(DS.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard()
    }

    /// Visible "+ Add holding" affordance. Adds directly to the focused portfolio;
    /// on "All Portfolios" it picks the one portfolio, or offers a menu to choose.
    @ViewBuilder private var addHoldingButton: some View {
        let label = HStack(spacing: 4) {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
            Text("Add holding").font(.inter(11, weight: .semibold, relativeTo: .caption))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Capsule().fill(DS.brand))

        switch scope {
        case .portfolio(let id):
            Button { addHoldingAction.perform(id) } label: { label }.buttonStyle(.plain)
                .help("Add a holding to this portfolio")
        case .all:
            if storageService.portfolios.count == 1, let id = storageService.portfolios.first?.id {
                Button { addHoldingAction.perform(id) } label: { label }.buttonStyle(.plain)
                    .help("Add a holding")
            } else if !storageService.portfolios.isEmpty {
                Menu {
                    ForEach(storageService.portfolios) { p in
                        Button(p.name) { addHoldingAction.perform(p.id) }
                    }
                } label: { label }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Add a holding — choose which portfolio")
            }
        }
    }

    var emptyLine: some View {
        Text("No holdings yet").font(DS.caption).foregroundStyle(DS.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
    }
}
