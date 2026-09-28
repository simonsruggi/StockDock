import SwiftUI

/// Uppercase, tracked, muted — the quiet label above a card's content.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(DS.label)
            .foregroundStyle(DS.inkSecondary)
            .tracking(0.8)
            .textCase(.uppercase)
    }
}
