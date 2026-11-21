import SwiftUI

/// Text-only action inside a settings card ("Send test", "Clear all", …).
struct SettingLinkButton: View {
    let title: String
    var tint: Color = DS.brand
    var enabled = true
    let action: () -> Void

    init(_ title: String, tint: Color = DS.brand, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.inter(12, weight: .medium, relativeTo: .caption))
                .foregroundStyle(enabled ? tint : DS.inkTertiary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
