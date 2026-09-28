import SwiftUI

/// Fully custom, desktop-grade watchlist: a hand-built sortable list (clickable
/// column headers, hover rows, right-click actions, Move Up/Down reorder) dressed
/// as a white card over the paper ground — no native `Table`.
struct WatchlistWideView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Binding var showSearch: Bool

    enum SortKey { case order, symbol, name, changePercent, extChangePercent }

    @State var filter = ""
    @State private var filterFocused = false
    @FocusState private var filterFieldFocused: Bool
    // Default to the manual "as added" order so Move Up/Down is meaningful;
    // clicking a column header re-sorts by that column (toggles direction).
    @State var sortKey: SortKey = .order
    @State var sortAsc = true
    @State private var addToPortfolio: AddTarget?
    @State private var alertSymbol: AlertTarget?

    struct AddTarget: Identifiable { let symbol: String; let portfolioId: UUID; var id: String { "\(symbol)-\(portfolioId)" } }
    struct AlertTarget: Identifiable { let symbol: String; var id: String { symbol } }
    struct DetailTarget: Identifiable { let symbol: String; var id: String { symbol } }
    @State private var detailSymbol: DetailTarget?
    @State private var renameSymbol: AlertTarget?

    private func toggleSort(_ key: SortKey) {
        if sortKey == key { sortAsc.toggle() } else { sortKey = key; sortAsc = (key == .order || key == .symbol || key == .name) }
    }

    var body: some View {
        PageScaffold("Watchlist", caption: "\(storageService.watchlist.count) symbols") {
            HStack(spacing: 12) {
                RefreshButton(isLoading: stockService.isLoading) {
                    Task { await stockService.refreshAll(storageService: storageService) }
                }
                filterField
                addButton
            }
        } content: {
            if storageService.watchlist.isEmpty {
                emptyState
            } else {
                table
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .premiumCard()
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, DS.gutter)
                    .frame(maxWidth: DS.contentMaxWidth + DS.gutter * 2)
            }
        }
        .navigationTitle("Watchlist")
        .task(id: storageService.watchlist) {
            // One batched spark request fills every row's sparkline.
            await stockService.ensureSparklines(for: storageService.watchlist)
        }
        .sheet(item: $addToPortfolio) { t in
            HoldingFormSheet(mode: .addSymbol(symbol: t.symbol, portfolioId: t.portfolioId)) { addToPortfolio = nil }
                .environmentObject(stockService).environmentObject(storageService)
        }
        .sheet(item: $alertSymbol) { t in
            PriceAlertSheet(symbol: t.symbol) { alertSymbol = nil }
                .environmentObject(stockService).environmentObject(storageService)
        }
        .sheet(item: $renameSymbol) { t in
            RenameSymbolSheet(symbol: t.symbol,
                              currentAlias: storageService.alias(for: t.symbol)) { renameSymbol = nil }
                .environmentObject(storageService)
        }
        .sheet(item: $detailSymbol) { t in
            SymbolDetailSheet(symbol: t.symbol, onAddToPortfolio: { pid in
                detailSymbol = nil
                // Let the detail sheet finish dismissing before presenting the add sheet.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    addToPortfolio = AddTarget(symbol: t.symbol, portfolioId: pid)
                }
            }) { detailSymbol = nil }
                .environmentObject(stockService).environmentObject(storageService)
        }
    }

    // MARK: - Header controls

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(DS.inkTertiary)
            TextField("Filter", text: $filter)
                .textFieldStyle(.plain)
                .font(DS.body)
                .focused($filterFieldFocused)
                .frame(width: 140)
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(DS.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(DS.cardAlt))
        .overlay(Capsule().strokeBorder(filterFieldFocused ? DS.brand : .clear, lineWidth: 1.5))
        .animation(.easeOut(duration: 0.15), value: filterFieldFocused)
    }

    private var addButton: some View {
        Button { showSearch = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                Text("Add").font(.inter(12, weight: .semibold, relativeTo: .body))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(Capsule().fill(DS.brand))
        }
        .buttonStyle(.plain)
        .help("Add a symbol to your watchlist")
    }

    // MARK: - Custom list

    private var table: some View {
        VStack(spacing: 0) {
            headerRow
            Divider().overlay(DS.hairline)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.element.id) { idx, row in
                        WatchRowView(row: row,
                                     showExtended: storageService.showExtendedHours,
                                     extendedSession: extendedSession,
                                     percentDecimals: storageService.percentDecimals,
                                     valueDecimals: storageService.valueDecimals,
                                     onOpen: { detailSymbol = DetailTarget(symbol: row.symbol) },
                                     menu: { rowMenu(row) })
                        if idx < visibleRows.count - 1 {
                            Divider().overlay(DS.hairline.opacity(0.5)).padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var headerRow: some View {
        HStack(spacing: WCol.spacing) {
            headerCell("Symbol", .symbol, width: WCol.symbol, align: .leading)
            headerCell("Name", .name, width: nil, align: .leading)
            headerCell("Price", .changePercent, width: WCol.price, align: .trailing,
                       help: "Sort by today's % change")
            if storageService.showExtendedHours {
                headerCell("After hrs", .extChangePercent, width: WCol.ext, align: .trailing,
                           help: "Sort by the pre/post-market % move")
            }
            Text("Trend").font(DS.label).foregroundStyle(DS.inkTertiary).frame(width: WCol.trend)
            Text("52-week").font(DS.label).foregroundStyle(DS.inkTertiary).frame(width: WCol.range, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func headerCell(_ title: String, _ key: SortKey, width: CGFloat?, align: Alignment,
                            help: LocalizedStringKey = "") -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { toggleSort(key) } } label: {
            HStack(spacing: 3) {
                if align == .trailing { Spacer(minLength: 0) }
                Text(LocalizedStringKey(title)).font(DS.label).foregroundStyle(sortKey == key ? DS.brand : DS.inkTertiary)
                if sortKey == key {
                    Image(systemName: sortAsc ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold)).foregroundStyle(DS.brand)
                }
                if align == .leading { Spacer(minLength: 0) }
            }
            .frame(width: width, alignment: align)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: align)
        .help(help)
    }

    @ViewBuilder
    private func rowMenu(_ row: WatchRow) -> some View {
        Button { detailSymbol = DetailTarget(symbol: row.symbol) } label: { Label("View Chart", systemImage: "chart.xyaxis.line") }
        if !storageService.portfolios.isEmpty {
            Menu {
                ForEach(storageService.portfolios) { p in
                    Button(p.name) { addToPortfolio = AddTarget(symbol: row.symbol, portfolioId: p.id) }
                }
            } label: { Label("Add to Portfolio", systemImage: "plus.rectangle.on.folder") }
        }
        Button { alertSymbol = AlertTarget(symbol: row.symbol) } label: { Label("Set Price Alert…", systemImage: "bell") }
        Button { renameSymbol = AlertTarget(symbol: row.symbol) } label: { Label("Rename…", systemImage: "pencil") }
        if let idx = storageService.watchlist.firstIndex(of: row.symbol) {
            Divider()
            Button { move(row.symbol, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                .disabled(idx == 0)
            Button { move(row.symbol, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                .disabled(idx == storageService.watchlist.count - 1)
        }
        Divider()
        Button(role: .destructive) { storageService.removeFromWatchlist(row.symbol) } label: {
            Label("Remove from Watchlist", systemImage: "trash")
        }
    }

    /// Moves a symbol up/down in the manual watchlist order (persisted), and
    /// shows the result — under a column sort the move would look inert.
    private func move(_ symbol: String, by delta: Int) {
        guard storageService.moveWatchlistItem(symbol, by: delta) else { return }
        sortKey = .order
        sortAsc = true
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "star").font(.system(size: 34)).foregroundStyle(DS.inkTertiary)
            Text("No stocks in your watchlist").font(DS.bodyStrong).foregroundStyle(DS.inkSecondary)
            addButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
