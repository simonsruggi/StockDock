import SwiftUI

struct PortfolioSection: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.addHoldingAction) var addHoldingAction
    let portfolio: Portfolio
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showNotifications = false

    private func exportSingle() {
        PortfolioIO.exportAll([portfolio], storageService: storageService, restoreActivationPolicy: true)
    }

    private var currSymbol: String {
        StorageService.currencySymbol(for: storageService.preferredCurrency)
    }

    private var totals: (value: Double, cost: Double) {
        PortfolioValuation.totals(PortfolioValuation.inputs(for: portfolio.holdings,
                                                             stockService: stockService, storageService: storageService))
    }

    var totalValue: Double { totals.value }

    var totalPnl: Double {
        totalValue - totalCost
    }

    var totalCost: Double { totals.cost }

    var totalPnlPercent: Double {
        guard abs(totalCost) >= 0.01 else { return 0 }
        return (totalPnl / abs(totalCost)) * 100
    }

    var body: some View {
        Section {
            // Summary row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total value")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                    Text(StorageService.formatAmount(totalValue, symbol: currSymbol, decimals: storageService.amountDecimals))
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("P&L")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                    HStack(spacing: 2) {
                        Text(StorageService.formatAmount(totalPnl, symbol: currSymbol, decimals: storageService.amountDecimals, signed: true))
                        Text(String(format: "(%.\(storageService.percentDecimals)f%%)", totalPnlPercent))
                    }
                    .font(.inter(13, relativeTo: .body).monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundColor(totalPnl >= 0 ? DS.up : DS.down)
                }
            }
            .padding(.vertical, 2)

            // Column headers
            if !portfolio.holdings.isEmpty {
                HStack(spacing: 0) {
                    Text("Symbol")
                        .frame(width: 80, alignment: .leading)
                    Text("Price")
                        .frame(maxWidth: .infinity)
                    Text("Value / P&L")
                        .frame(width: 120, alignment: .trailing)
                }
                .font(.inter(10, weight: .medium, relativeTo: .caption))
                .foregroundColor(.secondary)
                .padding(.vertical, 1)
            }

            // Holdings
            ForEach(portfolio.holdings) { holding in
                HoldingRow(holding: holding, portfolioId: portfolio.id)
            }

            // Add holding button
            Button(action: { addHoldingAction.perform(portfolio.id) }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add holding")
                }
                .font(.inter(10, relativeTo: .caption))
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
        } header: {
            if isRenaming {
                HStack {
                    TextField("Name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                        .onSubmit { commitRename() }
                    Button("OK") { commitRename() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(renameText.isEmpty)
                }
            } else {
                HStack {
                    Text(portfolio.name)
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                        // #14: excluded portfolios read as present-but-not-counted.
                        .foregroundColor(portfolio.isExcludedFromTotal ? .secondary : .primary)
                    if portfolio.isExcludedFromTotal {
                        Image(systemName: "briefcase.badge.minus")
                            .font(.inter(10, relativeTo: .caption))
                            .foregroundColor(.secondary)
                            .help("Not counted in the total")
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        renameText = portfolio.name
                        isRenaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        showNotifications = true
                    } label: {
                        Label("Notifications…", systemImage: "bell")
                    }
                    Button(action: exportSingle) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Toggle(isOn: Binding(
                        get: { !portfolio.isExcludedFromTotal },
                        set: { storageService.setExcludedFromTotal(!$0, id: portfolio.id) }
                    )) {
                        Label("Count in Total", systemImage: "sum")
                    }
                    Divider()
                    Button(role: .destructive) {
                        storageService.deletePortfolio(id: portfolio.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .popover(isPresented: $showNotifications, arrowEdge: .trailing) {
                    PortfolioNotificationsView(
                        portfolioId: portfolio.id,
                        portfolioName: portfolio.name,
                        onDismiss: { showNotifications = false }
                    )
                    .environmentObject(storageService)
                    .frame(width: 340)
                }
            }
        }
    }

    private func commitRename() {
        guard !renameText.isEmpty else { return }
        storageService.renamePortfolio(id: portfolio.id, name: renameText)
        isRenaming = false
    }
}
