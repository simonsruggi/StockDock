import SwiftUI

/// The sidebar's way into the search palette: looks like a field, opens ⌘K.
struct SidebarSearchButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                Text("Search").font(DS.body)
                Spacer()
                Text(verbatim: "⌘K")
                    .font(.inter(10, weight: .semibold, relativeTo: .caption2))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.card))
            }
            .foregroundStyle(DS.inkTertiary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? DS.card : DS.cardAlt))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Search stocks, portfolios, settings  ⌘K")
    }
}
