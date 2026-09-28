import SwiftUI

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
                let dateStr = DateFormatter.mediumDate.string(from: purchaseDate)
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
