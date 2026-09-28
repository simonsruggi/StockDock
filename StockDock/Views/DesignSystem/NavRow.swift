import SwiftUI

/// Premium sidebar entry: icon + title + optional trailing figure. The selection
/// pill slides between rows via `matchedGeometryEffect` when a namespace is given.
struct NavRow: View {
    let icon: String
    let title: String
    var trailing: String? = nil
    var trailingTint: Color = DS.inkTertiary
    var helpText: String? = nil
    /// #14: renders the row as present-but-inactive (secondary text, muted icon).
    /// Used for portfolios kept out of the combined total.
    var dimmed: Bool = false
    let selected: Bool
    var namespace: Namespace.ID? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium)).frame(width: 18)
                    .foregroundStyle(selected ? DS.brand : (dimmed ? DS.inkTertiary : DS.inkSecondary))
                Text(LocalizedStringKey(title))
                    .font(.inter(12.5, weight: selected ? .semibold : .regular, relativeTo: .body))
                    .foregroundStyle(dimmed ? DS.inkSecondary : DS.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(.inter(10.5, weight: .medium, relativeTo: .caption2).monospacedDigit())
                        .foregroundStyle(trailingTint)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background {
                if selected {
                    selectionPill
                } else if hover {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(helpText ?? title)
    }

    @ViewBuilder private var selectionPill: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.brand.opacity(0.13))
        if let namespace {
            shape.matchedGeometryEffect(id: "navSelection", in: namespace)
        } else {
            shape
        }
    }
}
