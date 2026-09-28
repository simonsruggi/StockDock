import SwiftUI

/// DS-styled one-shot price alert creation, editing and duplication.
struct PriceAlertSheet: View {
    enum Mode {
        case create
        case edit(PriceAlert)
        case duplicate(PriceAlert)
    }

    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService
    let symbol: String
    var mode: Mode = .create
    let onDismiss: () -> Void

    @State private var condition: AlertCondition = .priceAbove
    @State private var thresholdText = ""

    private var source: PriceAlert? {
        switch mode {
        case .create: return nil
        case .edit(let a), .duplicate(let a): return a
        }
    }
    private var title: String {
        switch mode {
        case .create: return "Alert · \(symbol)"
        case .edit: return "Edit alert · \(symbol)"
        case .duplicate: return "Duplicate alert · \(symbol)"
        }
    }
    private var confirmTitle: String {
        if case .edit = mode { return "Save" }
        return "Create alert"
    }

    private var quote: StockQuote? { stockService.quotes[symbol] }
    private var currencySymbol: String {
        StorageService.currencySymbol(for: quote?.currency ?? storageService.preferredCurrency)
    }
    private var thresholdUnit: String {
        condition.thresholdKind == .price ? currencySymbol : "%"
    }

    var body: some View {
        SheetShell(title: title, onCancel: onDismiss, width: 420) {
            FieldBlock("Condition") {
                DSPicker(options: AlertCondition.allCases.map { ($0, $0.label) },
                         selection: $condition, width: 260)
                    .onChange(of: condition) {
                        if condition != source?.condition { prefill() } else { loadSource() }
                    }
            }
            FieldBlock(thresholdLabel) {
                HStack(spacing: 8) {
                    DSTextField(placeholder: placeholder, text: $thresholdText, mono: true)
                    Text(thresholdUnit).font(DS.body).foregroundStyle(DS.inkSecondary)
                }
            }
            if let q = quote {
                Text("Current price: \(currencySymbol)\(StorageService.formatNumber(q.effectivePrice, decimals: 2))")
                    .font(DS.caption).foregroundStyle(DS.inkTertiary)
            }
            PrimaryButton(title: confirmTitle, enabled: parsedValue != nil, action: create)
        }
        .onAppear {
            if let source { condition = source.condition; loadSource() } else { prefill() }
        }
    }

    private var parsedValue: Double? {
        guard let v = Double(thresholdText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return v
    }

    private var thresholdLabel: String {
        switch condition {
        case .priceAbove, .priceBelow: return "Target price"
        case .dailyChangeUp, .dailyChangeDown: return "Daily change threshold"
        case .near52WeekHigh, .near52WeekLow: return "Proximity (within %)"
        }
    }
    private var placeholder: String { condition.thresholdKind == .price ? "0.00" : "5" }

    private func loadSource() {
        guard let source else { return }
        thresholdText = source.condition.thresholdKind == .price
            ? String(format: "%.2f", source.threshold)
            : String(format: "%g", source.threshold)
    }

    private func prefill() {
        switch condition.thresholdKind {
        case .price: if let q = quote { thresholdText = String(format: "%.2f", q.effectivePrice) }
        case .percent:
            switch condition {
            case .near52WeekHigh, .near52WeekLow: thresholdText = "2"
            default: thresholdText = "5"
            }
        }
    }

    private func create() {
        guard let v = parsedValue else { return }
        switch mode {
        case .create:
            storageService.addAlert(PriceAlert(symbol: symbol, condition: condition, threshold: v))
        case .edit(let a):
            storageService.updateAlert(id: a.id, condition: condition, threshold: v)
        case .duplicate(let a):
            storageService.addAlert(a.duplicate(condition: condition, threshold: v))
        }
        onDismiss()
    }
}
