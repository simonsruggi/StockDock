import SwiftUI

/// A collapsible settings category: a tappable header (icon + title + chevron)
/// that expands to reveal its controls. Keeps the (long) settings list short —
/// you drill into the category you need. Expansion state is owned by the caller
/// (persisted via @AppStorage) so it survives popover reopenings.
struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: icon)
                        .font(.inter(11, relativeTo: .caption))
                        .foregroundColor(.accentColor)
                        .frame(width: 16)
                    Text(title)
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.inter(10, weight: .semibold, relativeTo: .caption))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.leading, 25)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
        }
    }
}
