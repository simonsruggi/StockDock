import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Binding var showSearch: Bool
    @State var searchText = ""
    @State private var addToPortfolio: (symbol: String, portfolioId: UUID)? = nil
    @State private var alertSymbol: String? = nil
    @State private var renameSymbol: String? = nil
    // #23: the list opens in the order the user arranged, like the wide window
    // does. Clicking a column header sorts by it; clicking it once more past the
    // reversed direction comes back here.
    @State var sortColumn: SortColumn = .manual
    @State var sortAscending: Bool = false

    enum SortColumn {
        case manual, symbol, price, change

        /// Direction a column starts on when first picked.
        var initialAscending: Bool { self == .symbol }
    }

    /// Reordering only makes sense against the stored order, and the drag
    /// offsets only line up with `watchlist` when nothing is filtered out.
    private var canReorder: Bool { sortColumn == .manual && searchText.isEmpty }

    /// The drag handler, or nil when a drag would move the wrong row.
    private var reorderAction: ((IndexSet, Int) -> Void)? {
        guard canReorder else { return nil }
        return { source, destination in
            storageService.moveWatchlistItem(from: source, to: destination)
        }
    }

    var body: some View {
        if storageService.watchlist.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "star")
                    .font(.inter(32, relativeTo: .largeTitle))
                    .foregroundColor(.secondary)
                Text("No stocks in watchlist")
                    .foregroundColor(.secondary)
                Button("Add stock") {
                    showSearch = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.inter(10, relativeTo: .caption))
                TextField("Filter watchlist…", text: $searchText)
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

            HStack(spacing: 0) {
                sortHeader("Symbol", column: .symbol)
                    .frame(width: 80, alignment: .leading)
                sortHeader("Price", column: .price)
                    .frame(maxWidth: .infinity)
                sortHeader("Change", column: .change)
                    .frame(width: 120, alignment: .trailing)
            }
            .font(.inter(10, weight: .medium, relativeTo: .caption))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            Divider()

            List {
                ForEach(filteredSymbols, id: \.self) { symbol in
                    if let quote = stockService.quotes[symbol] {
                        QuoteRow(quote: quote)
                            .contextMenu {
                                watchlistContextMenu(symbol: symbol)
                            }
                    } else {
                        HStack {
                            Text(symbol)
                                .font(.inter(13, relativeTo: .body).monospacedDigit())
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        .contextMenu {
                            watchlistContextMenu(symbol: symbol)
                        }
                    }
                }
                .onDelete { offsets in
                    let currentList = filteredSymbols
                    let symbols = offsets.compactMap { idx in
                        idx < currentList.count ? currentList[idx] : nil
                    }
                    symbols.forEach { storageService.removeFromWatchlist($0) }
                }
                // #23: drag to arrange. `reorderAction` is nil while sorted or
                // filtered, which withholds the drag affordance rather than
                // offering one that would move the wrong row.
                .onMove(perform: reorderAction)

            }
            .listStyle(.plain)

            Divider()

            Button(action: { showSearch = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add stock")
                }
                .font(.inter(10, relativeTo: .caption))
            }
            .buttonStyle(.borderless)
            .padding(8)
            }
            .sheet(item: Binding<AddToPortfolioItem?>(
                get: {
                    if let atp = addToPortfolio {
                        return AddToPortfolioItem(symbol: atp.symbol, portfolioId: atp.portfolioId)
                    }
                    return nil
                },
                set: { addToPortfolio = $0.map { ($0.symbol, $0.portfolioId) } }
            )) { item in
                QuickAddHoldingView(symbol: item.symbol, portfolioId: item.portfolioId) {
                    addToPortfolio = nil
                }
                .environmentObject(stockService)
                .environmentObject(storageService)
                .frame(width: 300, height: storageService.advancedPositions ? 290 : 220)
            }
            .sheet(item: Binding<AlertSheetItem?>(
                get: { alertSymbol.map { AlertSheetItem(symbol: $0) } },
                set: { alertSymbol = $0?.symbol }
            )) { item in
                AlertEditView(symbol: item.symbol) { alertSymbol = nil }
                    .environmentObject(stockService)
                    .environmentObject(storageService)
                    .frame(width: 300, height: 260)
            }
            .sheet(item: Binding<AlertSheetItem?>(
                get: { renameSymbol.map { AlertSheetItem(symbol: $0) } },
                set: { renameSymbol = $0?.symbol }
            )) { item in
                RenameSymbolSheet(symbol: item.symbol,
                                  currentAlias: storageService.alias(for: item.symbol)) {
                    renameSymbol = nil
                }
                .environmentObject(storageService)
            }
        }
    }

    /// #23: three states per column — ascending, descending, then back to the
    /// user's own order, so a sort is never a one-way door.
    private func cycleSort(_ column: SortColumn) {
        if sortColumn != column {
            sortColumn = column
            sortAscending = column.initialAscending
        } else if sortAscending == column.initialAscending {
            sortAscending.toggle()
        } else {
            sortColumn = .manual
        }
    }

    private func sortHeader(_ title: String, column: SortColumn) -> some View {
        let hint: String = sortColumn == column
            ? "Click again to return to your own order"
            : "Sort by \(title.lowercased())"
        return Button(action: { cycleSort(column) }) {
            HStack(spacing: 2) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.inter(8, relativeTo: .caption2))
                }
            }
        }
        .buttonStyle(.plain)
        .help(hint)
    }

    @ViewBuilder
    private func watchlistContextMenu(symbol: String) -> some View {
        if !storageService.portfolios.isEmpty {
            Menu {
                ForEach(storageService.portfolios) { portfolio in
                    Button(portfolio.name) {
                        addToPortfolio = (symbol, portfolio.id)
                    }
                }
            } label: {
                Label("Add to Portfolio", systemImage: "plus.rectangle.on.folder")
            }
            Divider()
        }
        Button {
            alertSymbol = symbol
        } label: {
            Label("Set Price Alert…", systemImage: "bell")
        }
        Button {
            renameSymbol = symbol
        } label: {
            Label("Rename…", systemImage: "pencil")
        }
        // #23: the same reorder actions the wide window offers — they work
        // while the list is sorted or filtered, when dragging cannot.
        if let idx = storageService.watchlist.firstIndex(of: symbol) {
            Divider()
            Button { move(symbol, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                .disabled(idx == 0)
            Button { move(symbol, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                .disabled(idx == storageService.watchlist.count - 1)
        }
        Divider()
        Button(role: .destructive) {
            storageService.removeFromWatchlist(symbol)
        } label: {
            Label("Remove from Watchlist", systemImage: "trash")
        }
    }

    /// Moves a symbol one place up/down in the stored order, and shows the
    /// result: reordering while sorted by a column would otherwise look inert.
    private func move(_ symbol: String, by delta: Int) {
        guard storageService.moveWatchlistItem(symbol, by: delta) else { return }
        sortColumn = .manual
    }
}

private struct AddToPortfolioItem: Identifiable {
    let symbol: String
    let portfolioId: UUID
    var id: String { "\(symbol)-\(portfolioId)" }
}

private struct AlertSheetItem: Identifiable {
    let symbol: String
    var id: String { symbol }
}
