import SwiftUI

// Desktop-window input sheets, styled in the "private banking" design system
// (Inter, emerald, cards) so they match the window instead of the small popover
// forms. They reuse the SAME StorageService/StockService logic — only the
// presentation is new. The compact popover versions stay for the menu bar.

/// Shared sheet chrome: title + Cancel, DS ground, fixed width.
struct SheetShell<Content: View>: View {
    let title: String
    let onCancel: () -> Void
    var width: CGFloat = 460
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title)).font(DS.titleXL).tracking(-0.3).foregroundStyle(DS.ink)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.inter(12, weight: .medium, relativeTo: .body))
                    .foregroundStyle(DS.inkSecondary)
                    .keyboardShortcut(.cancelAction)
            }
            content
        }
        .padding(24)
        .frame(width: width)
        .background(DS.ground)
    }
}
