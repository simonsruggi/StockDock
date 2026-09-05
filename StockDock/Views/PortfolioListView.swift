import SwiftUI
import UniformTypeIdentifiers

struct PortfolioListView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @State private var showNewPortfolio = false
    @State private var newPortfolioName = ""
    @State private var searchText = ""
    @State private var importAlert: String?

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
                }
                .padding(8)
            }
        }
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
            total + portfolio.holdings.reduce(0) { sum, holding in
                guard let quote = stockService.quotes[holding.symbol] else { return sum }
                let rate = stockService.rate(from: quote.currency)
                return sum + holding.marketValue(currentPrice: quote.displayPrice(extendedHours: storageService.showExtendedHours)) * rate
            }
        }
    }

    private var grandTotalCost: Double {
        storageService.countedPortfolios.reduce(0) { total, portfolio in
            total + portfolio.holdings.reduce(0) { sum, holding in
                guard let quote = stockService.quotes[holding.symbol] else { return sum }
                let rate = stockService.rate(from: quote.currency, for: holding.purchaseDate)
                return sum + holding.costBasisLocal * rate
            }
        }
    }

    private struct GlobalPosition: Identifiable {
        let id: String            // symbol
        let avgPrice: Double      // weighted avg buy price, in the price currency
        let currentPrice: Double  // latest quote price, same currency as avgPrice
        let priceSymbol: String
        let pct: Double           // price return vs. avg (position-direction aware)
        let value: Double         // market value (preferred currency), for sorting
        var symbol: String { id }
    }

    /// Per-symbol weighted-average buy price across ALL portfolios, with the
    /// current price return vs. that average. Sorted by market value.
    private var globalPositions: [GlobalPosition] {
        var qty: [String: Double] = [:]
        var qtyPrice: [String: Double] = [:]
        for portfolio in storageService.countedPortfolios {
            for h in portfolio.holdings {
                qty[h.symbol, default: 0] += h.quantity
                qtyPrice[h.symbol, default: 0] += h.quantity * h.avgPrice
            }
        }
        return qty.compactMap { symbol, q -> GlobalPosition? in
            guard abs(q) >= 1e-9, let quote = stockService.quotes[symbol] else { return nil }
            let avg = qtyPrice[symbol, default: 0] / q
            let price = quote.displayPrice(extendedHours: storageService.showExtendedHours)
            let rawPct = abs(avg) >= 1e-6 ? (price / avg - 1) * 100 : 0
            // A short position gains when the price falls, so flip the sign.
            let pct = q >= 0 ? rawPct : -rawPct
            let priced = stockService.priceDisplay(for: quote.currency)
            let priceSymbol = StorageService.currencySymbol(for: priced.currency)
            let value = abs(price * q) * stockService.rate(from: quote.currency)
            return GlobalPosition(id: symbol, avgPrice: avg * priced.rate, currentPrice: price * priced.rate,
                                  priceSymbol: priceSymbol, pct: pct, value: value)
        }
        .sorted { $0.value > $1.value }
    }

    private func exportPortfolios(_ portfolios: [Portfolio]) {
        PortfolioIO.exportAll(portfolios, storageService: storageService, restoreActivationPolicy: true)
    }

    private func importPortfolios() {
        PortfolioIO.importInto(storageService, restoreActivationPolicy: true) { message in
            self.importAlert = message
        }
    }

    private func createPortfolio() {
        guard !newPortfolioName.isEmpty else { return }
        storageService.addPortfolio(name: newPortfolioName)
        newPortfolioName = ""
        showNewPortfolio = false
    }
}

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

    var totalValue: Double {
        portfolio.holdings.reduce(0) { sum, holding in
            guard let quote = stockService.quotes[holding.symbol] else { return sum }
            let rate = stockService.rate(from: quote.currency)
            return sum + holding.marketValue(currentPrice: quote.displayPrice(extendedHours: storageService.showExtendedHours)) * rate
        }
    }

    var totalPnl: Double {
        totalValue - totalCost
    }

    var totalCost: Double {
        portfolio.holdings.reduce(0) { sum, holding in
            guard let quote = stockService.quotes[holding.symbol] else { return sum }
            let rate = stockService.rate(from: quote.currency, for: holding.purchaseDate)
            return sum + holding.costBasisLocal * rate
        }
    }

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

struct HoldingRow: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.editHoldingAction) var editHoldingAction
    let holding: Holding
    let portfolioId: UUID

    var quote: StockQuote? {
        stockService.quotes[holding.symbol]
    }

    /// #24: the price-display conversion for this row, decided once so the
    /// figure and the symbol always come from the same source.
    private var priced: (rate: Double, currency: String) {
        guard let quote else { return (1.0, "") }
        return stockService.priceDisplay(for: quote.currency)
    }

    private func formatQty(_ qty: Double) -> String {
        qty == qty.rounded(.down) ? String(format: "%.0f", qty) : String(format: "%.2f", qty)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1: Ticker + Qty@Avg
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text(holding.symbol)
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.bold)
                    if holding.isShort {
                        Text("SHORT")
                            .font(.inter(8, weight: .bold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(DS.down))
                    }
                    if holding.effectiveLeverage != 1 {
                        Text("\(StorageService.formatNumber(holding.effectiveLeverage, decimals: holding.effectiveLeverage == holding.effectiveLeverage.rounded() ? 0 : 1))\u{00D7}")
                            .font(.inter(8, weight: .bold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 2).fill(DS.brand))
                    }
                }
                // #24: the avg price sits right under the Last column, so it has
                // to be in the same currency — it was printed raw while Last was
                // converted, which is what made people convert it by hand.
                Text("\(formatQty(holding.quantity))\u{00D7}\(StorageService.formatNumber(holding.avgPrice * priced.rate, decimals: 2))")
                    .font(.inter(10, relativeTo: .caption).monospacedDigit())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 88, alignment: .leading)

            if let quote {
                let rate = stockService.rate(from: quote.currency)
                let pRate = priced.rate
                let priceSymbol = StorageService.currencySymbol(for: priced.currency)
                let prefSymbol = StorageService.currencySymbol(for: storageService.preferredCurrency)

                // Col 2: Price + badge
                HStack(spacing: 3) {
                    Text("\(priceSymbol)\(StorageService.formatNumber(quote.displayPrice(extendedHours: storageService.showExtendedHours) * pRate, decimals: storageService.resolvedPriceDecimals(symbol: quote.symbol, price: quote.displayPrice(extendedHours: storageService.showExtendedHours) * pRate)))")
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
                                    .fill(quote.marketState.hasPrefix("PRE") ? DS.gold : DS.palette[3])
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                // Col 3: Controvalore + P&L in preferred currency
                let displayPrice = quote.displayPrice(extendedHours: storageService.showExtendedHours)
                let marketVal = holding.marketValue(currentPrice: displayPrice) * rate
                let costRate = stockService.rate(from: quote.currency, for: holding.purchaseDate)
                let costBasis = holding.costBasisLocal * costRate
                let pnl = marketVal - costBasis
                let pnlPct = abs(costBasis) >= 0.01 ? (pnl / abs(costBasis)) * 100 : 0

                VStack(alignment: .trailing, spacing: 1) {
                    Text(StorageService.formatAmount(marketVal, symbol: prefSymbol, decimals: storageService.amountDecimals))
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.medium)
                    Text("\(StorageService.formatAmount(pnl, symbol: prefSymbol, decimals: storageService.amountDecimals, signed: true)) (\(String(format: "%.\(storageService.percentDecimals)f%%", pnlPct)))")
                        .font(.inter(10, relativeTo: .caption).monospacedDigit())
                        .foregroundColor(pnl >= 0 ? DS.up : DS.down)
                }
                .frame(width: 120, alignment: .trailing)
            } else {
                Spacer()
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                editHoldingAction.perform(portfolioId, holding)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                storageService.removeHolding(from: portfolioId, holdingId: holding.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct EditHoldingView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    let portfolioId: UUID
    let holding: Holding
    @Binding var isPresented: (portfolioId: UUID, holding: Holding)?

    @State private var quantityText: String
    @State private var avgPriceText: String
    @State private var leverageText: String
    @State private var isShort: Bool
    @State private var purchaseDate: Date

    init(portfolioId: UUID, holding: Holding, isPresented: Binding<(portfolioId: UUID, holding: Holding)?>) {
        self.portfolioId = portfolioId
        self.holding = holding
        self._isPresented = isPresented
        // Quantity is edited as a positive magnitude; the Long/Short picker holds the sign.
        _quantityText = State(initialValue: String(format: "%.2f", abs(holding.quantity)))
        _avgPriceText = State(initialValue: String(format: "%.2f", holding.avgPrice))
        _leverageText = State(initialValue: (holding.leverage.map { $0 != 1 ? String(format: "%g", $0) : "" }) ?? "")
        _isShort = State(initialValue: holding.quantity < 0)
        _purchaseDate = State(initialValue: holding.purchaseDate ?? Date())
    }

    /// #24: names the currency the stored avg price is in, so it is never
    /// mistaken for the converted figure shown in the list.
    private var avgPriceLabel: String {
        guard let currency = stockService.quotes[holding.symbol]?.currency, !currency.isEmpty
        else { return "Avg price" }
        return "Avg price (\(currency))"
    }

    private var costBasisInfo: (costInStock: Double, rate: Double, costInPreferred: Double)? {
        guard let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: ".")),
              let quote = stockService.quotes[holding.symbol],
              qty != 0, price > 0
        else { return nil }
        let costInStock = price * qty
        let rate = stockService.rate(from: quote.currency, for: purchaseDate)
        return (costInStock, rate, costInStock * rate)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Edit \(holding.symbol)")
                    .font(.inter(13, weight: .bold, relativeTo: .headline))
                Spacer()
                Button("Close") { isPresented = nil }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.top)

            if storageService.advancedPositions {
                VStack(alignment: .leading) {
                    Text("Position")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                    Picker("Position", selection: $isShort) {
                        Text("Long").tag(false)
                        Text("Short").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.horizontal)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Quantity")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                    TextField("0", text: $quantityText)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading) {
                    Text(avgPriceLabel)
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                    TextField("0.00", text: $avgPriceText)
                        .textFieldStyle(.roundedBorder)
                }
                if storageService.advancedPositions {
                    VStack(alignment: .leading) {
                        Text("Leverage")
                            .font(.inter(10, relativeTo: .caption))
                            .foregroundColor(.secondary)
                        TextField("1\u{00D7}", text: $leverageText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                    }
                }
            }
            .padding(.horizontal)

            if storageService.advancedPositions {
                Text("Pick Long or Short. Leverage multiplies P&L and exposure (empty = 1\u{00D7}).")
                    .font(.inter(10, relativeTo: .caption))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading) {
                Text("Purchase date")
                    .font(.inter(10, relativeTo: .caption))
                    .foregroundColor(.secondary)
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
            }
            .padding(.horizontal)

            if let quote = stockService.quotes[holding.symbol], quote.currency != storageService.preferredCurrency, let info = costBasisInfo {
                let stockSym = StorageService.currencySymbol(for: quote.currency)
                let prefSym = StorageService.currencySymbol(for: storageService.preferredCurrency)
                let dateStr = Self.dateFormatter.string(from: purchaseDate)
                Text("Cost basis: \(prefSym)\(String(format: "%.2f", info.costInPreferred)) (\(stockSym)\(String(format: "%.2f", info.costInStock)) × \(String(format: "%.4f", info.rate)) on \(dateStr))")
                    .font(.inter(10, relativeTo: .caption))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }

            Spacer()

            Button("Save") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(quantityText.isEmpty || avgPriceText.isEmpty)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                await stockService.ensureHistoricalRate(for: Holding(id: holding.id, symbol: holding.symbol, quantity: holding.quantity, avgPrice: holding.avgPrice, purchaseDate: purchaseDate))
            }
        }
        .onChange(of: purchaseDate) { _, _ in
            Task {
                await stockService.ensureHistoricalRate(for: Holding(id: holding.id, symbol: holding.symbol, quantity: Double(quantityText.replacingOccurrences(of: ",", with: ".")) ?? 0, avgPrice: Double(avgPriceText.replacingOccurrences(of: ",", with: ".")) ?? 0, purchaseDate: purchaseDate))
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func save() {
        let advanced = storageService.advancedPositions
        guard let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: ".")),
              price > 0, abs(qty) > 0
        else { return }
        // When Advanced is off, keep the holding's existing direction and
        // leverage so a plain edit never silently flips a short or drops leverage.
        let short = advanced ? isShort : (holding.quantity < 0)
        let signedQty = short ? -abs(qty) : abs(qty)
        let leverage: Double? = {
            guard advanced else { return holding.leverage }
            guard let l = Double(leverageText.replacingOccurrences(of: ",", with: ".")),
                  l > 0, l != 1
            else { return nil }
            return l
        }()
        storageService.updateHolding(in: portfolioId, holdingId: holding.id, quantity: signedQty, avgPrice: price, purchaseDate: purchaseDate, leverage: leverage)
        Task {
            await stockService.refreshAll(storageService: storageService)
        }
        isPresented = nil
    }
}
