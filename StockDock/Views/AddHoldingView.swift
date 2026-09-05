import SwiftUI

struct AddHoldingView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    let portfolioId: UUID
    @Binding var isPresented: UUID?

    @State private var searchText = ""
    @State private var quantityText = ""
    @State private var avgPriceText = ""
    @State private var leverageText = ""
    @State private var isShort = false
    @State private var purchaseDate = Date()
    @State private var searchResults: [SearchResult] = []
    @State private var selectedSymbol: String?
    @State private var searchTask: Task<Void, Never>?

    /// #24: the avg price is stored in the stock's own currency, whatever the
    /// display settings say. Naming that currency on the field is what stops
    /// people converting the figure by hand before typing it in.
    private var avgPriceLabel: String {
        guard let symbol = selectedSymbol,
              let currency = stockService.quotes[symbol]?.currency,
              !currency.isEmpty
        else { return "Avg price" }
        return "Avg price (\(currency))"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add holding")
                    .font(.inter(13, weight: .bold, relativeTo: .headline))
                Spacer()
                Button("Close") { isPresented = nil }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.top)

            // Symbol search
            if let selected = selectedSymbol {
                HStack {
                    Text(selected)
                        .font(.inter(13, relativeTo: .body).monospacedDigit())
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: {
                        selectedSymbol = nil
                        searchText = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            } else {
                TextField("Symbol, name or ISIN (e.g. AAPL, IE00B4L5Y983)", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .onChange(of: searchText) { _, newValue in
                        searchTask?.cancel()
                        guard newValue.count >= 1 else {
                            searchResults = []
                            return
                        }
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            guard !Task.isCancelled else { return }
                            searchResults = await stockService.search(query: newValue)
                        }
                    }

                if !searchResults.isEmpty {
                    List(searchResults.prefix(5)) { result in
                        Button(action: {
                            searchTask?.cancel()
                            selectedSymbol = result.symbol
                            searchResults = []
                            if let quote = stockService.quotes[result.symbol] {
                                avgPriceText = String(format: "%.2f", quote.price)
                            }
                        }) {
                            HStack {
                                Text(result.symbol)
                                    .fontWeight(.semibold)
                                Text(result.name)
                                    .font(.inter(10, relativeTo: .caption))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .frame(height: min(CGFloat(searchResults.prefix(5).count) * 30, 150))
                }
            }

            // Position type (Advanced)
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

            // Quantity & price
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

            Spacer()

            Button("Add") {
                addHolding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSymbol == nil || quantityText.isEmpty || avgPriceText.isEmpty)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addHolding() {
        let advanced = storageService.advancedPositions
        guard let sym = selectedSymbol,
              let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: ".")),
              price > 0, abs(qty) > 0
        else { return }

        // Quantity is entered as a positive magnitude; the Long/Short picker
        // (Advanced only) decides the sign.
        let signedQty = (advanced && isShort) ? -abs(qty) : abs(qty)
        let leverage = parsedLeverage()
        storageService.addHolding(to: portfolioId, symbol: sym, quantity: signedQty, avgPrice: price, purchaseDate: purchaseDate, leverage: leverage)
        Task {
            await stockService.refreshAll(storageService: storageService)
        }
        isPresented = nil
    }

    /// Parsed leverage, or nil when advanced mode is off, the field is empty, or
    /// the value is an unlevered 1× — so unlevered holdings stay clean in storage.
    private func parsedLeverage() -> Double? {
        guard storageService.advancedPositions,
              let l = Double(leverageText.replacingOccurrences(of: ",", with: ".")),
              l > 0, l != 1
        else { return nil }
        return l
    }
}
