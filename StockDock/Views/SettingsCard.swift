import SwiftUI

/// A premium card holding a stack of setting rows.
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
                .padding(.bottom, 4)
            content
        }
        .padding(.horizontal, DS.pad)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard()
    }
}
