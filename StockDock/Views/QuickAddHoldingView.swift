import SwiftUI

struct QuickAddHoldingView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    let symbol: String
    let portfolioId: UUID
    let onDismiss: () -> Void

    @State private var quantityText = ""
    @State private var avgPriceText = ""
    @State private var leverageText = ""
    @State private var isShort = false
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

            if storageService.advancedPositions {
                VStack(alignment: .leading) {
                    Text("Position").font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                    Picker("Position", selection: $isShort) {
                        Text("Long").tag(false)
                        Text("Short").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
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
                if storageService.advancedPositions {
                    VStack(alignment: .leading) {
                        Text("Leverage").font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                        TextField("1\u{00D7}", text: $leverageText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                    }
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
                      abs(qty) > 0, price > 0
                else { return }
                let advanced = storageService.advancedPositions
                let signedQty = (advanced && isShort) ? -abs(qty) : abs(qty)
                let leverage: Double? = {
                    guard advanced,
                          let l = Double(leverageText.replacingOccurrences(of: ",", with: ".")),
                          l > 0, l != 1
                    else { return nil }
                    return l
                }()
                storageService.addHolding(to: portfolioId, symbol: symbol, quantity: signedQty, avgPrice: price, purchaseDate: purchaseDate, leverage: leverage)
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
