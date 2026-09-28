import SwiftUI

/// Issue #12: give a symbol a custom display name, for tickers that read badly in
/// the menu bar ("CAD/USD", "^GSPC"). Saving an empty field clears the alias and
/// falls back to the ticker, so there's no separate "reset" affordance to find.
struct RenameSymbolSheet: View {
    @EnvironmentObject var storageService: StorageService
    let symbol: String
    let onDismiss: () -> Void
    @State private var name: String

    init(symbol: String, currentAlias: String, onDismiss: @escaping () -> Void) {
        self.symbol = symbol
        self.onDismiss = onDismiss
        _name = State(initialValue: currentAlias)
    }

    var body: some View {
        SheetShell(title: "Rename \(symbol)", onCancel: onDismiss, width: 380) {
            FieldBlock("Display name") {
                DSTextField(placeholder: symbol, text: $name)
            }
            PrimaryButton(title: "Save", enabled: true, action: save)
        }
    }

    private func save() {
        storageService.setAlias(name, for: symbol)
        onDismiss()
    }
}
