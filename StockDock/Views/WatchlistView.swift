import SwiftUI

struct WatchlistView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Binding var showSearch: Bool
    @State private var searchText = ""
    @State private var addToPortfolio: (symbol: String, portfolioId: UUID)? = nil
    @State private var alertSymbol: String? = nil
    @State private var sortColumn: SortColumn = .change
    @State private var sortAscending: Bool = false

    enum SortColumn {
        case symbol, price, change
    }

    var sortedSymbols: [String] {
        storageService.watchlist.sorted { a, b in
            let qa = stockService.quotes[a]
            let qb = stockService.quotes[b]
            let result: Bool
            switch sortColumn {
            case .symbol:
                result = a.localizedCompare(b) == .orderedAscending
            case .price:
                let pa = qa?.price ?? 0
                let pb = qb?.price ?? 0
                result = pa < pb
            case .change:
                let ca = qa?.changePercent ?? 0
                let cb = qb?.changePercent ?? 0
                result = ca < cb
            }
            return sortAscending ? result : !result
        }
    }

    var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return sortedSymbols }
        let query = searchText.lowercased()
        return sortedSymbols.filter { symbol in
            symbol.lowercased().contains(query) ||
            (stockService.quotes[symbol]?.name.lowercased().contains(query) ?? false) ||
            (storageService.isinMap[symbol]?.lowercased().contains(query) ?? false)
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
                .frame(width: 300, height: 220)
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
        }
    }

    @ViewBuilder
    private func sortHeader(_ title: String, column: SortColumn) -> some View {
        Button(action: {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = column == .symbol
            }
        }) {
            HStack(spacing: 2) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.inter(8, relativeTo: .caption2))
                }
            }
        }
        .buttonStyle(.plain)
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
        Divider()
        Button(role: .destructive) {
            storageService.removeFromWatchlist(symbol)
        } label: {
            Label("Remove from Watchlist", systemImage: "trash")
        }
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

struct QuickAddHoldingView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    let symbol: String
    let portfolioId: UUID
    let onDismiss: () -> Void

    @State private var quantityText = ""
    @State private var avgPriceText = ""
    @State private var purchaseDate = Date()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add \(symbol)")
                    .font(.inter(13, weight: .bold, relativeTo: .headline))
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Quantity").font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                    TextField("0", text: $quantityText)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text("Avg price").font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                    TextField("0.00", text: $avgPriceText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading) {
                Text("Purchase date").font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }

            Spacer()

            Button("Add") {
                guard let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
                      let price = Double(avgPriceText.replacingOccurrences(of: ",", with: ".")),
                      qty > 0, price > 0
                else { return }
                storageService.addHolding(to: portfolioId, symbol: symbol, quantity: qty, avgPrice: price, purchaseDate: purchaseDate)
                Task { await stockService.refreshAll(storageService: storageService) }
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(quantityText.isEmpty || avgPriceText.isEmpty)
        }
        .padding()
        .onAppear {
            // Pre-fill current price
            if let quote = stockService.quotes[symbol] {
                avgPriceText = String(format: "%.2f", quote.price)
            }
        }
    }
}

struct QuoteRow: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    let quote: StockQuote

    private var displayCurrency: String {
        let pref = storageService.stockPriceCurrency
        return pref.isEmpty ? quote.currency : pref
    }

    private var priceRate: Double {
        stockService.priceRate(from: quote.currency)
    }

    private var currSymbol: String {
        StorageService.currencySymbol(for: displayCurrency)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1: Symbol + name
            VStack(alignment: .leading, spacing: 1) {
                Text(quote.symbol)
                    .font(.inter(13, relativeTo: .body).monospacedDigit())
                    .fontWeight(.bold)
                if storageService.showCompanyName {
                    Text(quote.name)
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 80, alignment: .leading)

            // Col 2: Price + day range
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Text("\(currSymbol)\(String(format: "%.2f", quote.displayPrice(extendedHours: storageService.showExtendedHours) * priceRate))")
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.medium)
                    if storageService.showExtendedHours, quote.isExtendedHours, !quote.marketStateLabel.isEmpty {
                        Text(quote.marketStateLabel)
                            .font(.inter(9, weight: .semibold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(quote.marketState.hasPrefix("PRE") ? .orange : .purple)
                            )
                    }
                }
                if storageService.showDayRange, let high = quote.dayHigh, let low = quote.dayLow {
                    Text(String(format: "%.2f – %.2f", low * priceRate, high * priceRate))
                        .font(.inter(10, relativeTo: .caption).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                if storageService.show52WeekBar,
                   let pos = quote.fiftyTwoWeekPosition,
                   let low = quote.fiftyTwoWeekLow, let high = quote.fiftyTwoWeekHigh {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0f", low * priceRate))
                            .font(.inter(8, relativeTo: .caption2).monospacedDigit())
                            .foregroundColor(.secondary)
                        RangeBar(position: pos)
                            .frame(width: 56)
                        Text(String(format: "%.0f", high * priceRate))
                            .font(.inter(8, relativeTo: .caption2).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .help("52-week range")
                }
            }
            .frame(maxWidth: .infinity)

            // Col 3: Change
            VStack(alignment: .trailing, spacing: 1) {
                if storageService.showAbsoluteChange {
                    Text(StorageService.formatAmount(quote.change * priceRate, symbol: currSymbol, signed: true))
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.medium)
                        .foregroundColor(quote.isPositive ? .green : .red)
                }
                Text(String(format: "%.1f%%", quote.changePercent))
                    .font(.inter(10, relativeTo: .caption).monospacedDigit())
                    .foregroundColor(quote.isPositive ? .green : .red)

                if storageService.showExtendedHours,
                   let extChg = quote.extendedChange,
                   let extPct = quote.extendedChangePercent {
                    Text(String(format: "%+.2f (%.1f%%)", extChg * priceRate, extPct))
                        .font(.inter(10, relativeTo: .caption).monospacedDigit())
                        .foregroundColor(extChg >= 0 ? .green.opacity(0.8) : .red.opacity(0.8))
                }
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
