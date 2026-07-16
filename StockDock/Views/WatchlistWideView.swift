import SwiftUI

/// Fully custom, desktop-grade watchlist: a hand-built sortable list (clickable
/// column headers, hover rows, right-click actions, Move Up/Down reorder) dressed
/// as a white card over the paper ground — no native `Table`.
struct WatchlistWideView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Binding var showSearch: Bool

    enum SortKey { case order, symbol, name, price, extPrice, changePercent }

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

    private var rows: [WatchRow] {
        storageService.watchlist.enumerated().map { index, symbol in
            let q = stockService.quotes[symbol]
            let rate = q.map { stockService.priceRate(from: $0.currency) } ?? 1
            let ext: Double? = q.flatMap { $0.isExtendedHours ? $0.effectivePrice * rate : nil }
            return WatchRow(
                id: symbol, order: index, symbol: symbol,
                name: q?.name ?? "",
                currency: (storageService.stockPriceCurrency.isEmpty ? q?.currency : storageService.stockPriceCurrency) ?? "",
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
        case .price:         return by { $0.price }
        case .changePercent: return by { $0.changePercent }
        case .extPrice:
            // Rows without an extended-hours price sort to the bottom either way.
            return base.sorted { a, b in
                switch (a.extPrice, b.extPrice) {
                case let (x?, y?): return asc ? x < y : x > y
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return false
                }
            }
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
            headerCell("Price", .price, width: WCol.price, align: .trailing)
            headerCell("After hrs", .extPrice, width: WCol.ext, align: .trailing)
            headerCell("Change", .changePercent, width: WCol.change, align: .trailing)
            Text("Trend").font(DS.label).foregroundStyle(DS.inkTertiary).frame(width: WCol.trend)
            Text("52-week").font(DS.label).foregroundStyle(DS.inkTertiary).frame(width: WCol.range, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func headerCell(_ title: String, _ key: SortKey, width: CGFloat?, align: Alignment) -> some View {
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

    /// Moves a symbol up/down in the manual watchlist order (persisted).
    private func move(_ symbol: String, by delta: Int) {
        guard let i = storageService.watchlist.firstIndex(of: symbol) else { return }
        let j = i + delta
        guard j >= 0, j < storageService.watchlist.count else { return }
        storageService.watchlist.swapAt(i, j)
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
    static let price: CGFloat = 88
    static let ext: CGFloat = 112
    static let change: CGFloat = 104
    static let trend: CGFloat = 56
    static let range: CGFloat = 100
    static let spacing: CGFloat = 12
}

/// One custom watchlist row: hover tint, click-to-open, right-click actions.
private struct WatchRowView<Menu: View>: View {
    let row: WatchlistWideView.WatchRow
    let percentDecimals: Int
    let valueDecimals: Int
    let onOpen: () -> Void
    @ViewBuilder let menu: () -> Menu
    @State private var hover = false

    /// Price decimals honoring the manual override (Auto = smart per #10).
    private func priceDec(_ price: Double) -> Int {
        valueDecimals >= 0 ? valueDecimals : StorageService.priceDecimals(symbol: row.symbol, price: price)
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
                    Text(row.symbol).font(DS.figure).foregroundStyle(DS.ink)
                }
                .frame(width: WCol.symbol, alignment: .leading)

                // Name
                Text(row.name.isEmpty ? "—" : row.name)
                    .font(DS.body).foregroundStyle(DS.inkSecondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Price
                Group {
                    if row.loaded {
                        Text("\(StorageService.currencySymbol(for: row.currency))\(StorageService.formatNumber(row.price, decimals: priceDec(row.price)))")
                            .font(DS.figure).foregroundStyle(DS.ink)
                            .contentTransition(.numericText())
                    } else {
                        DSSpinner(size: 12)
                    }
                }
                .frame(width: WCol.price, alignment: .trailing)

                // After-hours / pre-market price + its own % move
                Group {
                    if let ext = row.extPrice {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(StorageService.currencySymbol(for: row.currency))\(StorageService.formatNumber(ext, decimals: priceDec(ext)))")
                                .font(DS.figure).foregroundStyle(DS.inkSecondary)
                                .contentTransition(.numericText())
                            HStack(spacing: 4) {
                                Text(LocalizedStringKey(row.extLabel))
                                    .font(DS.micro).foregroundStyle(DS.inkTertiary)
                                if let p = row.extChangePercent {
                                    Text(String(format: "%+.\(percentDecimals)f%%", p))
                                        .font(DS.micro).foregroundStyle(DS.pnlColor(p))
                                }
                            }
                        }
                    } else {
                        Text("—").font(DS.figure).foregroundStyle(DS.inkTertiary)
                    }
                }
                .frame(width: WCol.ext, alignment: .trailing)

                // Change
                Group {
                    if row.loaded {
                        VStack(alignment: .trailing, spacing: 2) {
                            ChangePill(value: row.changePercent,
                                       text: String(format: "%+.\(percentDecimals)f%%", row.changePercent))
                            Text(StorageService.formatAmount(row.change, symbol: StorageService.currencySymbol(for: row.currency), signed: true))
                                .font(DS.micro).foregroundStyle(DS.inkTertiary)
                        }
                    } else {
                        Text("—").font(DS.figure).foregroundStyle(DS.inkTertiary)
                    }
                }
                .frame(width: WCol.change, alignment: .trailing)

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
