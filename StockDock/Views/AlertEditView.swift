import SwiftUI

/// Sheet for creating a one-shot price alert for a given symbol.
struct AlertEditView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService

    let symbol: String
    let onDismiss: () -> Void

    @State private var condition: AlertCondition = .priceAbove
    @State private var thresholdText: String = ""

    private var quote: StockQuote? { stockService.quotes[symbol] }

    private var currencySymbol: String {
        StorageService.currencySymbol(for: quote?.currency ?? storageService.preferredCurrency)
    }

    private var thresholdUnit: String {
        switch condition.thresholdKind {
        case .price: return currencySymbol
        case .percent: return "%"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Alert for \(symbol)")
                    .font(.inter(13, weight: .bold, relativeTo: .headline))
                Spacer()
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Condition")
                    .font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                Picker("Condition", selection: $condition) {
                    ForEach(AlertCondition.allCases, id: \.self) { c in
                        Text(c.label).tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: condition) { prefillThreshold() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(thresholdLabel)
                    .font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                HStack(spacing: 6) {
                    TextField(placeholder, text: $thresholdText)
                        .textFieldStyle(.roundedBorder)
                    Text(thresholdUnit)
                        .font(.inter(11, relativeTo: .body)).foregroundColor(.secondary)
                }
            }

            if let q = quote {
                Text("Current price: \(currencySymbol)\(String(format: "%.2f", q.effectivePrice))")
                    .font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
            }

            Spacer()

            Button("Create Alert") {
                guard let value = Double(thresholdText.replacingOccurrences(of: ",", with: ".")),
                      value > 0 else { return }
                storageService.addAlert(PriceAlert(symbol: symbol, condition: condition, threshold: value))
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(Double(thresholdText.replacingOccurrences(of: ",", with: ".")) == nil)
        }
        .padding()
        .onAppear { prefillThreshold() }
    }

    private var thresholdLabel: String {
        switch condition {
        case .priceAbove, .priceBelow: return "Target price"
        case .dailyChangeUp, .dailyChangeDown: return "Daily change threshold"
        case .near52WeekHigh, .near52WeekLow: return "Proximity (within %)"
        }
    }

    private var placeholder: String {
        condition.thresholdKind == .price ? "0.00" : "5"
    }

    /// Sensible defaults when switching condition.
    private func prefillThreshold() {
        switch condition.thresholdKind {
        case .price:
            if let q = quote { thresholdText = String(format: "%.2f", q.effectivePrice) }
        case .percent:
            switch condition {
            case .near52WeekHigh, .near52WeekLow:
                thresholdText = "2"
            default:
                thresholdText = "5"
            }
        }
    }
}
