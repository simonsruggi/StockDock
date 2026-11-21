import SwiftUI

/// A collapsible settings category for the menu bar popover: a header (icon +
/// title + chevron) that opens a white card of setting rows, the same rows the
/// desktop Settings uses. Expansion state is owned by the caller (persisted via
/// @AppStorage) so it survives popover reopenings.
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
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.brand)
                        .frame(width: 18)
                    Text(LocalizedStringKey(title))
                        .font(DS.bodyStrong)
                        .foregroundStyle(DS.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.inkTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline))
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
