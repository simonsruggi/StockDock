import SwiftUI

/// A single alert level inside a symbol group: condition, re-arm toggle and delete.
struct AlertRow: View {
    @EnvironmentObject var storageService: StorageService
    @Environment(\.editAlert) private var editAlert
    let alert: PriceAlert
    /// A symbol's only alert sits at the top level, so it carries the symbol itself.
    var showsSymbol = false

    private var currencySymbol: String {
        StorageService.currencySymbol(for: StockService.shared.quotes[alert.symbol]?.currency
            ?? storageService.preferredCurrency)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: alert.condition.systemImage)
                .font(.inter(10, relativeTo: .caption))
                .foregroundColor(alert.isEnabled ? .accentColor : .secondary)
                .frame(width: 14)
            if showsSymbol {
                Text(alert.symbol)
                    .font(.inter(12, weight: .semibold, relativeTo: .body))
            }
            Text(AlertEvaluator.describeShort(alert, currencySymbol: currencySymbol))
                .font(.inter(11, relativeTo: .caption))
                .foregroundColor(alert.isEnabled ? .primary : .secondary)
            Spacer()
            if !alert.isEnabled {
                Text("triggered")
                    .font(.inter(8, weight: .semibold, relativeTo: .caption2))
                    .foregroundColor(.orange)
            }
            Toggle("", isOn: Binding(
                get: { alert.isEnabled },
                set: { storageService.setAlertEnabled(id: alert.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(alert.isEnabled ? "Enabled" : "Re-arm alert")
            Button(action: { storageService.removeAlert(id: alert.id) }) {
                Image(systemName: "trash")
                    .font(.inter(10, relativeTo: .caption))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            if let editAlert {
                Button("Edit…") { editAlert(alert, false) }
                Button("Duplicate…") { editAlert(alert, true) }
                Divider()
            }
            Button("Delete", role: .destructive) { storageService.removeAlert(id: alert.id) }
        }
    }
}
