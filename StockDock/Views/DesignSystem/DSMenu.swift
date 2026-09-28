import SwiftUI
import AppKit

/// One row in a `DSMenu`.
struct DSMenuAction: Identifiable {
    let id = UUID()
    var title: String
    var icon: String
    var destructive: Bool = false
    var action: () -> Void
}

/// A design-system dropdown: a button that opens a DS-styled popover of rows
/// (Inter, emerald hover, red for destructive), instead of the native NSMenu.
struct DSMenu<Label: View>: View {
    var width: CGFloat = 210
    /// Sections are separated by a divider.
    let sections: [[DSMenuAction]]
    @ViewBuilder var label: () -> Label
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $show, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { si, section in
                        if si > 0 { Divider().overlay(DS.hairline).padding(.vertical, 3) }
                        ForEach(section) { item in
                            DSMenuRow(item: item) { show = false }
                        }
                    }
                }
                .padding(6)
                .frame(width: width)
            }
    }
}

private struct DSMenuRow: View {
    let item: DSMenuAction
    let dismiss: () -> Void
    @State private var hover = false

    var body: some View {
        Button { dismiss(); item.action() } label: {
            HStack(spacing: 9) {
                Image(systemName: item.icon).font(.system(size: 12)).frame(width: 16)
                Text(LocalizedStringKey(item.title)).font(.inter(12.5, relativeTo: .body))
                Spacer(minLength: 8)
            }
            .foregroundStyle(item.destructive ? DS.down : DS.ink)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? (item.destructive ? DS.down.opacity(0.10) : DS.brand.opacity(0.10)) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
