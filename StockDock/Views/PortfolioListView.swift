import SwiftUI
import UniformTypeIdentifiers

struct PortfolioListView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @State private var showNewPortfolio = false
    @State private var newPortfolioName = ""
    @State private var searchText = ""
    @State private var importAlert: String?
    @State private var importCandidates: ImportCandidates?
    @State private var confirmDeleteAll = false
    /// Quanto è alto davvero l'elenco aggregato, per non riservargli spazio vuoto.
    @State private var globalsHeight: CGFloat = 0

    /// Il tetto dell'elenco aggregato dentro il popover, che è fisso a 380×520. Quel che
    /// resta serve al riepilogo sopra e alla lista dei portafogli sotto, che deve restare
    /// visibile e raggiungibile.
    private static let maxGlobalsHeight: CGFloat = 180

    var filteredPortfolios: [Portfolio] {
        guard !searchText.isEmpty else { return storageService.portfolios }
        let query = searchText.lowercased()
        return storageService.portfolios.filter { portfolio in
            portfolio.name.lowercased().contains(query) ||
            portfolio.holdings.contains { $0.symbol.lowercased().contains(query) }
        }
    }

    var body: some View {
        Group {
        if storageService.portfolios.isEmpty && !showNewPortfolio {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "briefcase")
                    .font(.inter(32, relativeTo: .largeTitle))
                    .foregroundColor(.secondary)
                Text("No portfolios")
                    .foregroundColor(.secondary)
                Button("Create portfolio") {
                    showNewPortfolio = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button(action: importPortfolios) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(.inter(10, relativeTo: .caption))
                }
                .buttonStyle(.borderless)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.inter(10, relativeTo: .caption))
                    TextField("Filter portfolios…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.inter(10, relativeTo: .caption))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.inter(10, relativeTo: .caption))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Divider()

                // Grand total
                if storageService.portfolios.count > 0 {
                    let currSym = StorageService.currencySymbol(for: storageService.preferredCurrency)
                    let grandTotal = grandTotalValue
                    let grandCost = grandTotalCost
                    let grandPnl = grandTotal - grandCost
                    // Use the magnitude of the cost basis so long/short baskets
                    // (where the signed cost can be near zero) still report a %.
                    let grandPnlPct = abs(grandCost) >= 0.01 ? (grandPnl / abs(grandCost)) * 100 : 0

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total value")
                                .font(.inter(10, relativeTo: .caption))
                                .foregroundColor(.secondary)
                            Text(StorageService.formatAmount(grandTotal, symbol: currSym, decimals: storageService.amountDecimals))
                                .font(.inter(13, relativeTo: .body).monospacedDigit())
                                .fontWeight(.bold)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("P&L")
                                .font(.inter(10, relativeTo: .caption))
                                .foregroundColor(.secondary)
                            HStack(spacing: 2) {
                                Text(StorageService.formatAmount(grandPnl, symbol: currSym, decimals: storageService.amountDecimals, signed: true))
                                Text(String(format: "(%.\(storageService.percentDecimals)f%%)", grandPnlPct))
                            }
                            .font(.inter(13, relativeTo: .body).monospacedDigit())
                            .fontWeight(.bold)
                            .foregroundColor(grandPnl >= 0 ? DS.up : DS.down)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    // Per-symbol average buy price, aggregated across ALL portfolios,
                    // with the price return vs. that average.
                    let globals = globalPositions
                    if !globals.isEmpty {
                        Divider()
                        // Scrolls inside its own bounded area instead of growing with the
                        // number of symbols. The popover is a fixed 380×520: past ~25
                        // holdings an unbounded list pushed the header off the top and the
                        // portfolio list, "New portfolio" and Import/Export off the bottom,
                        // leaving them unreachable (reported in #21).
                        //
                        // The cap is a share of the popover, not a row count: what matters
                        // is how much room is left for everything else, and rows grow with
                        // the user's text size.
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(globals) { p in
                                    HStack(spacing: 8) {
                                        Text(p.symbol)
                                            .font(.inter(11, relativeTo: .caption).monospacedDigit())
                                            .fontWeight(.semibold)
                                            .frame(width: 62, alignment: .leading)
                                        Text("avg \(StorageService.formatAmount(p.avgPrice, symbol: p.priceSymbol, decimals: StorageService.priceDecimals(symbol: p.symbol, price: p.avgPrice)))")
                                            .font(.inter(11, relativeTo: .caption).monospacedDigit())
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                        Text("now \(StorageService.formatAmount(p.currentPrice, symbol: p.priceSymbol, decimals: StorageService.priceDecimals(symbol: p.symbol, price: p.currentPrice)))")
                                            .font(.inter(11, relativeTo: .caption).monospacedDigit())
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                        Spacer()
                                        Text(String(format: "%+.\(storageService.percentDecimals)f%%", p.pct))
                                            .font(.inter(11, relativeTo: .caption).monospacedDigit())
                                            .fontWeight(.medium)
                                            .foregroundColor(p.pct >= 0 ? DS.up : DS.down)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            // L'altezza vera del contenuto: con pochi titoli il riquadro
                            // si stringe su di essa, invece di lasciare un vuoto alto
                            // quanto il tetto.
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(key: GlobalsHeightKey.self, value: g.size.height)
                                }
                            )
                        }
                        .onPreferenceChange(GlobalsHeightKey.self) { globalsHeight = $0 }
                        .frame(height: min(globalsHeight, Self.maxGlobalsHeight))
                        .scrollBounceBehavior(.basedOnSize)
                    }

                    Divider()
                }

                List {
                    if showNewPortfolio {
                        HStack {
                            TextField("Portfolio name", text: $newPortfolioName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    createPortfolio()
                                }
                            Button("OK") {
                                createPortfolio()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newPortfolioName.isEmpty)
                        }
                        .padding(.vertical, 4)
                    }

                    ForEach(filteredPortfolios) { portfolio in
                        PortfolioSection(portfolio: portfolio)
                    }
                    .onDelete { offsets in
                        let currentList = filteredPortfolios
                        let ids = offsets.compactMap { idx in
                            idx < currentList.count ? currentList[idx].id : nil
                        }
                        ids.forEach { storageService.deletePortfolio(id: $0) }
                    }
                }
                .listStyle(.plain)

                Divider()

                HStack {
                    Button(action: { showNewPortfolio = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("New portfolio")
                        }
                        .font(.inter(10, relativeTo: .caption))
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button(action: importPortfolios) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import")
                        }
                        .font(.inter(10, relativeTo: .caption))
                    }
                    .buttonStyle(.borderless)

                    Button(action: { exportPortfolios(storageService.portfolios) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export All")
                        }
                        .font(.inter(10, relativeTo: .caption))
                    }
                    .buttonStyle(.borderless)
                    .disabled(storageService.portfolios.isEmpty)

                    Button(action: { confirmDeleteAll = true }) {
                        Image(systemName: "trash")
                            .font(.inter(10, relativeTo: .caption))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(DS.down)
                    .disabled(storageService.portfolios.isEmpty)
                    .help("Delete all portfolios")
                }
                .padding(8)
            }
        }
        }
        // The popover would close on the first click inside the sheet otherwise.
        .onChange(of: importCandidates == nil) { _, closed in
            (NSApp.delegate as? AppDelegate)?.holdPopoverOpen(!closed)
        }
        .sheet(item: $importCandidates) { c in
            ImportPortfoliosSheet(candidates: c.portfolios, width: 360) { count in
                importCandidates = nil
                if let count { importAlert = PortfolioIO.importedMessage(count) }
            }
            .environmentObject(storageService)
        }
        .alert("Delete all portfolios", isPresented: $confirmDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all", role: .destructive) { storageService.deleteAllPortfolios() }
        } message: {
            Text("Every portfolio, with its notifications and history, will be deleted. This cannot be undone.")
        }
        .alert("Import", isPresented: Binding(get: { importAlert != nil }, set: { if !$0 { importAlert = nil } })) {
            Button("OK") { importAlert = nil }
        } message: {
            Text(importAlert ?? "")
        }
    }

    // #14: grand totals and the cross-portfolio position list count only the
    // portfolios the user hasn't excluded.
    private var grandTotalValue: Double {
        storageService.countedPortfolios.reduce(0) { total, portfolio in
            total + portfolioTotals(portfolio).value
        }
    }

    private var grandTotalCost: Double {
        storageService.countedPortfolios.reduce(0) { total, portfolio in
            total + portfolioTotals(portfolio).cost
        }
    }

    private func portfolioTotals(_ portfolio: Portfolio) -> (value: Double, cost: Double) {
        PortfolioValuation.totals(PortfolioValuation.inputs(for: portfolio.holdings,
                                                             stockService: stockService, storageService: storageService))
    }

    private var globalPositions: [GlobalPosition] {
        GlobalPosition.all(storage: storageService, stocks: stockService)
    }

    private func exportPortfolios(_ portfolios: [Portfolio]) {
        PortfolioIO.exportAll(portfolios, storageService: storageService, restoreActivationPolicy: true)
    }

    private func importPortfolios() {
        PortfolioIO.pickImportFile(storageService, fromPopover: true,
                                   onLoaded: { importCandidates = ImportCandidates(portfolios: $0) },
                                   onAlert: { importAlert = $0 })
    }

    private func createPortfolio() {
        guard !newPortfolioName.isEmpty else { return }
        storageService.addPortfolio(name: newPortfolioName)
        newPortfolioName = ""
        showNewPortfolio = false
    }
}

/// L'altezza del contenuto dell'elenco aggregato, misurata mentre viene disegnato.
///
/// Serve perché uno `ScrollView` prende tutta l'altezza che gli viene offerta: senza
/// misura, chi ha tre titoli si ritroverebbe un riquadro alto come il tetto e mezzo vuoto.
private struct GlobalsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
