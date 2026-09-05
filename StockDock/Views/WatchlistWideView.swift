import SwiftUI

/// Fully custom, desktop-grade watchlist: a hand-built sortable list (clickable
/// column headers, hover rows, right-click actions, Move Up/Down reorder) dressed
/// as a white card over the paper ground — no native `Table`.
struct WatchlistWideView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Binding var showSearch: Bool

    enum SortKey { case order, symbol, name, changePercent, extChangePercent }

    @State private var filter = ""
    @State private var filterFocused = false
    @FocusState private var filterFieldFocused: Bool
    // Default to the manual "as added" order so Move Up/Down is meaningful;
    // clicking a column header re-sorts by that column (toggles direction).
    @State private var sortKey: SortKey = .order
    @State private var sortAsc = true
    @State private var addToPortfolio: AddTarget?
    @State private var alertSymbol: AlertTarget?

    struct WatchRow: Identifiable {
        let id: String
        let order: Int
        let symbol: String
        /// #12: user-chosen display name, "" when unset.
        let alias: String
        let name: String
        let currency: String
        let price: Double            // regular market price
        let extPrice: Double?        // pre/post-market price, if any
        let extChangePercent: Double? // pre/post-market % move vs regular close
        let extLabel: String         // "Pre" / "Post"
        let change: Double
        let changePercent: Double
        let loaded: Bool
        let quote: StockQuote?
    }
    struct AddTarget: Identifiable { let symbol: String; let portfolioId: UUID; var id: String { "\(symbol)-\(portfolioId)" } }
    struct AlertTarget: Identifiable { let symbol: String; var id: String { symbol } }
    struct DetailTarget: Identifiable { let symbol: String; var id: String { symbol } }
    @State private var detailSymbol: DetailTarget?
    @State private var renameSymbol: AlertTarget?

    private var rows: [WatchRow] {
        storageService.watchlist.enumerated().map { index, symbol in
            let q = stockService.quotes[symbol]
            // #24: rate and currency come from one call, so the figure and the
            // symbol agree even while the FX pair is still loading.
            let priced = q.map { stockService.priceDisplay(for: $0.currency) }
            let rate = priced?.rate ?? 1
            let ext: Double? = q.flatMap { $0.isExtendedHours ? $0.effectivePrice * rate : nil }
            return WatchRow(
                id: symbol, order: index, symbol: symbol,
                alias: storageService.alias(for: symbol),
                name: q?.name ?? "",
                currency: priced?.currency ?? "",
                price: (q?.price ?? 0) * rate,
                extPrice: ext,
                extChangePercent: ext != nil ? q?.extendedChangePercent : nil,
                extLabel: q?.marketStateLabel ?? "",
                change: (q?.change ?? 0) * rate,
                changePercent: q?.changePercent ?? 0,
                loaded: q != nil, quote: q
            )
        }
    }

    private var visibleRows: [WatchRow] {
        let sorted = sortedRows()
        guard !filter.isEmpty else { return sorted }
        let f = filter.lowercased()
        return sorted.filter { $0.symbol.lowercased().contains(f) || $0.name.lowercased().contains(f) }
    }

    /// True when any watchlist quote is trading pre/post-market. Drives the row
    /// hierarchy: during extended hours the After-hrs price/% reads first and the
    /// regular price dims to context; during regular hours it's the reverse.
    private var extendedSession: Bool {
        storageService.showExtendedHours &&
        storageService.watchlist.contains { stockService.quotes[$0]?.isExtendedHours == true }
    }

    private func sortedRows() -> [WatchRow] {
        let base = rows
        let asc = sortAsc
        func by<T: Comparable>(_ key: (WatchRow) -> T) -> [WatchRow] {
            base.sorted { asc ? key($0) < key($1) : key($0) > key($1) }
        }
        switch sortKey {
        case .order:         return asc ? base : base.reversed()
        case .symbol:        return by { $0.symbol }
        case .name:          return by { $0.name }
        case .changePercent: return by { $0.changePercent }
        case .extChangePercent:
            // The After-hrs column is hidden when Extended Hours is off, so its
            // sort key would be stranded — fall back to the manual order.
            guard storageService.showExtendedHours else { return asc ? base : base.reversed() }
            // Sort by the pre/post-market % move, not the raw extended price.
            // Rows without an extended-hours quote sink to the bottom either way.
            return StorageService.sortedByExtendedPercent(base, ascending: asc) { $0.extChangePercent }
        }
    }

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

/// Shared column widths so the header lines up with every row.
/// File-scope `private` = visible to both `WatchlistWideView` and `WatchRowView`.
private enum WCol {
    static let symbol: CGFloat = 128
    static let price: CGFloat = 104
    static let ext: CGFloat = 116
    static let trend: CGFloat = 56
    static let range: CGFloat = 100
    static let spacing: CGFloat = 12
}

/// One custom watchlist row: hover tint, click-to-open, right-click actions.
private struct WatchRowView<Menu: View>: View {
    let row: WatchlistWideView.WatchRow
    let showExtended: Bool
    let extendedSession: Bool
    let percentDecimals: Int
    let valueDecimals: Int
    let onOpen: () -> Void
    @ViewBuilder let menu: () -> Menu
    @State private var hover = false

    /// What the Name column shows: the company name, prefixed with the real
    /// ticker when the user renamed the symbol.
    private var nameColumn: String {
        let base = row.name.isEmpty ? "—" : row.name
        return row.alias.isEmpty ? base : "\(row.symbol) · \(base)"
    }

    /// Price decimals honoring the manual override (Auto = smart per #10).
    private func priceDec(_ price: Double) -> Int {
        valueDecimals >= 0 ? valueDecimals : StorageService.priceDecimals(symbol: row.symbol, price: price)
    }

    /// A price stacked over its own % move (same baseline, so they always agree).
    /// `emphasised` = the live session: the price goes ink-dark and the % becomes
    /// a coloured pill. Otherwise both dim so the active session reads first.
    @ViewBuilder
    private func pairedCell(price: Double, pct: Double?, label: String?, emphasised: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(StorageService.currencySymbol(for: row.currency))\(StorageService.formatNumber(price, decimals: priceDec(price)))")
                .font(DS.figure)
                .foregroundStyle(emphasised ? DS.ink : DS.inkTertiary)
                .contentTransition(.numericText())
            if let pct {
                HStack(spacing: 4) {
                    if let label, !label.isEmpty {
                        Text(LocalizedStringKey(label)).font(DS.micro).foregroundStyle(DS.inkTertiary)
                    }
                    if emphasised {
                        ChangePill(value: pct, text: String(format: "%+.\(percentDecimals)f%%", pct))
                    } else {
                        Text(String(format: "%+.\(percentDecimals)f%%", pct))
                            .font(DS.micro).foregroundStyle(DS.pnlColor(pct).opacity(0.55))
                    }
                }
            }
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: WCol.spacing) {
                // Symbol + chip
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.brand.opacity(0.10))
                        .frame(width: 28, height: 28)
                        .overlay(Text(row.symbol.prefix(2))
                            .font(.inter(9.5, weight: .bold, relativeTo: .caption2))
                            .foregroundStyle(DS.brand))
                    Text(row.alias.isEmpty ? row.symbol : row.alias)
                        .font(DS.figure).foregroundStyle(DS.ink).lineLimit(1)
                }
                .frame(width: WCol.symbol, alignment: .leading)

                // Name — prefixed with the real ticker when a custom name is set,
                // so renaming never hides what the row actually tracks.
                Text(nameColumn)
                    .font(DS.body).foregroundStyle(DS.inkSecondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Regular price + today's % move. Emphasised when the regular
                // session is the live one; dims to context during extended hours.
                Group {
                    if row.loaded {
                        pairedCell(price: row.price, pct: row.changePercent,
                                   label: nil, emphasised: !extendedSession)
                    } else {
                        DSSpinner(size: 12)
                    }
                }
                .frame(width: WCol.price, alignment: .trailing)

                // After-hours price + its pre/post % move. Only shown when the
                // Extended Hours setting is on; emphasised during extended hours
                // so the live move reads first.
                if showExtended {
                    Group {
                        if let ext = row.extPrice {
                            pairedCell(price: ext, pct: row.extChangePercent,
                                       label: row.extLabel, emphasised: extendedSession)
                        } else {
                            Text("—").font(DS.figure).foregroundStyle(DS.inkTertiary)
                        }
                    }
                    .frame(width: WCol.ext, alignment: .trailing)
                }

                // Trend sparkline
                Sparkline(symbol: row.symbol).frame(width: WCol.trend)

                // 52-week range
                Group {
                    if let q = row.quote, let pos = q.fiftyTwoWeekPosition {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.cardAlt).frame(height: 5)
                                Circle().fill(.white)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().strokeBorder(DS.brand, lineWidth: 1.5))
                                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 0.5)
                                    .offset(x: CGFloat(pos) * (geo.size.width - 9))
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 12)
                    } else {
                        Text("—").foregroundStyle(DS.inkTertiary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: WCol.range)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(minHeight: 44)
            .background(hover ? DS.cardAlt.opacity(0.6) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu { menu() }
    }
}
