import SwiftUI

/// A brand-filled primary button (Add / Save / Create).
struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.inter(13, weight: .semibold, relativeTo: .body))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(enabled ? DS.brand : DS.inkTertiary))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(.defaultAction)
    }
}
