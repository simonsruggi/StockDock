import SwiftUI

/// Add or edit a holding, DS-styled and wide. One view for three flows.
struct HoldingFormSheet: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    enum Mode {
        case add(portfolioId: UUID)
        case addSymbol(symbol: String, portfolioId: UUID)
        case edit(portfolioId: UUID, holding: Holding)
    }
    let mode: Mode
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedSymbol: String?
    @State private var quantityText = ""
    @State private var avgPriceText = ""
    @State private var leverageText = ""
    @State private var isShort = false
    @State private var purchaseDate = Date()

    private var portfolioId: UUID {
        switch mode {
        case .add(let id), .addSymbol(_, let id), .edit(let id, _): return id
        }
    }
    private var editingHolding: Holding? {
        if case .edit(_, let h) = mode { return h }
        return nil
    }
    private var isEditing: Bool { editingHolding != nil }
    private var fixedSymbol: String? {
        switch mode {
        case .addSymbol(let s, _): return s
        case .edit(_, let h): return h.symbol
        case .add: return nil
        }
    }
    private var symbol: String? { fixedSymbol ?? selectedSymbol }

    /// #24: the avg price is stored in the stock's own currency, not in the one
    /// the lists display prices in. Naming it on the field is what stops people
    /// converting the figure by hand before typing it in.
    private var avgPriceLabel: String {
        guard let sym = symbol,
              let currency = stockService.quotes[sym]?.currency,
              !currency.isEmpty
        else { return "Avg price" }
        return "Avg price (\(currency))"
    }

    private var title: String {
        if let h = editingHolding { return "Edit \(h.symbol)" }
        return "Add holding"
    }

    var body: some View {
        SheetShell(title: title, onCancel: onDismiss) {
            // Symbol
            if let sym = symbol {
                symbolChip(sym, removable: fixedSymbol == nil)
            } else {
                searchField
            }

            if storageService.advancedPositions {
                FieldBlock("Position") {
                    SegmentedRangePicker(options: [false, true],
                                         label: { $0 ? "Short" : "Long" },
                                         selection: $isShort)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                FieldBlock("Quantity") { DSTextField(placeholder: "0", text: $quantityText, mono: true) }
                FieldBlock(avgPriceLabel) { DSTextField(placeholder: "0.00", text: $avgPriceText, mono: true) }
                if storageService.advancedPositions {
                    FieldBlock("Leverage") { DSTextField(placeholder: "1×", text: $leverageText, mono: true) }
                        .frame(width: 90)
                }
            }

            FieldBlock("Purchase date") {
                DSDatePicker(date: $purchaseDate)
            }

            if let info = costBasisInfo {
                Text(info).font(DS.caption).foregroundStyle(DS.inkTertiary)
            }

            PrimaryButton(title: isEditing ? "Save" : "Add", enabled: canSave, action: save)
        }
        .onAppear(perform: prefill)
    }

    // MARK: Symbol UI

    private func symbolChip(_ sym: String, removable: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.brand.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay(Text(sym.prefix(2)).font(.inter(10, weight: .bold, relativeTo: .caption2)).foregroundStyle(DS.brand))
            Text(sym).font(.inter(14, weight: .semibold, relativeTo: .body).monospacedDigit()).foregroundStyle(DS.ink)
            if let name = stockService.quotes[sym]?.name, !name.isEmpty {
                Text(name).font(DS.caption).foregroundStyle(DS.inkTertiary).lineLimit(1)
            }
            Spacer()
            if removable {
                Button { selectedSymbol = nil; searchText = ""; searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.inkTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.cardAlt))
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldBlock("Symbol") {
                DSTextField(placeholder: "Symbol, name or ISIN (e.g. AAPL)", text: $searchText)
                    .onChange(of: searchText) { _, new in runSearch(new) }
            }
            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults.prefix(6)) { r in
                        Button { select(r) } label: {
                            HStack(spacing: 8) {
                                Text(r.symbol).font(DS.figure).foregroundStyle(DS.ink)
                                Text(r.name).font(DS.caption).foregroundStyle(DS.inkTertiary).lineLimit(1)
                                Spacer()
                                Text(r.exchange).font(DS.micro).foregroundStyle(DS.inkTertiary)
                            }
                            .padding(.vertical, 7).padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if r.id != searchResults.prefix(6).last?.id {
                            Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline))
            }
        }
    }

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        guard q.count >= 1 else { searchResults = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            searchResults = await stockService.search(query: q)
        }
    }

    private func select(_ r: SearchResult) {
        searchTask?.cancel()
        selectedSymbol = r.symbol
        searchResults = []
        if let q = stockService.quotes[r.symbol] { avgPriceText = String(format: "%.2f", q.price) }
    }

    // MARK: Logic

    private var canSave: Bool {
        symbol != nil &&
        Double(quantityText.replacingOccurrences(of: ",", with: ".")).map { abs($0) > 0 } == true &&
        Double(avgPriceText.replacingOccurrences(of: ",", with: ".")).map { $0 > 0 } == true
    }

    private var costBasisInfo: String? {
        guard let sym = symbol,
              let quote = stockService.quotes[sym],
              quote.currency != storageService.preferredCurrency,
              let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: ".")),
              qty != 0, price > 0 else { return nil }
        let stockSym = StorageService.currencySymbol(for: quote.currency)
        let prefSym = StorageService.currencySymbol(for: storageService.preferredCurrency)
        let rate = stockService.rate(from: quote.currency, for: purchaseDate)
        let costStock = price * abs(qty)
        return "Cost basis: \(prefSym)\(String(format: "%.2f", costStock * rate))  (\(stockSym)\(String(format: "%.2f", costStock)) × \(String(format: "%.4f", rate)))"
    }

    private func prefill() {
        if let h = editingHolding {
            quantityText = String(format: "%.2f", abs(h.quantity))
            avgPriceText = String(format: "%.2f", h.avgPrice)
            leverageText = (h.leverage.map { $0 != 1 ? String(format: "%g", $0) : "" }) ?? ""
            isShort = h.quantity < 0
            purchaseDate = h.purchaseDate ?? Date()
        } else if let sym = fixedSymbol, let q = stockService.quotes[sym] {
            avgPriceText = String(format: "%.2f", q.price)
        }
    }

    private func save() {
        let advanced = storageService.advancedPositions
        guard let sym = symbol,
              let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: ".")),
              price > 0, abs(qty) > 0 else { return }
        // Keep existing direction/leverage on a plain edit with Advanced off.
        let short = advanced ? isShort : (editingHolding?.quantity ?? 0) < 0
        let signedQty = short ? -abs(qty) : abs(qty)
        let leverage: Double? = {
            guard advanced else { return editingHolding?.leverage }
            guard let l = Double(leverageText.replacingOccurrences(of: ",", with: ".")), l > 0, l != 1 else { return nil }
            return l
        }()
        if let h = editingHolding {
            storageService.updateHolding(in: portfolioId, holdingId: h.id, quantity: signedQty, avgPrice: price, purchaseDate: purchaseDate, leverage: leverage)
        } else {
            storageService.addHolding(to: portfolioId, symbol: sym, quantity: signedQty, avgPrice: price, purchaseDate: purchaseDate, leverage: leverage)
        }
        Task { await stockService.refreshAll(storageService: storageService) }
        onDismiss()
    }
}
