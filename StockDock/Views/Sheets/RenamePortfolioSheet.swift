import SwiftUI

struct RenamePortfolioSheet: View {
    @EnvironmentObject var storageService: StorageService
    let portfolioId: UUID
    let onDismiss: () -> Void
    @State private var name: String

    init(portfolioId: UUID, currentName: String, onDismiss: @escaping () -> Void) {
        self.portfolioId = portfolioId
        self.onDismiss = onDismiss
        _name = State(initialValue: currentName)
    }

    var body: some View {
        SheetShell(title: "Rename portfolio", onCancel: onDismiss, width: 380) {
            FieldBlock("Name") { DSTextField(placeholder: "Portfolio name", text: $name) }
            PrimaryButton(title: "Save", enabled: !trimmed.isEmpty, action: save)
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private func save() {
        guard !trimmed.isEmpty else { return }
        storageService.renamePortfolio(id: portfolioId, name: trimmed)
        onDismiss()
    }
}
