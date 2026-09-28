import SwiftUI
import AppKit

/// A subtle support button (Star / Sponsor) that opens a URL and warms to a tint
/// on hover.
struct SupportButton: View {
    let icon: String
    let title: String
    let hoverTint: Color
    let url: String
    var compact: Bool = false
    @State private var hover = false

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Group {
                if compact {
                    Image(systemName: hover ? "\(icon).fill" : icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(hover ? hoverTint.opacity(0.14) : DS.cardAlt))
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: hover ? "\(icon).fill" : icon).font(.system(size: 11, weight: .medium))
                        Text(LocalizedStringKey(title)).font(.inter(11, weight: .medium, relativeTo: .caption))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hover ? hoverTint.opacity(0.10) : DS.cardAlt))
                }
            }
            .foregroundStyle(hover ? hoverTint : DS.inkSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(title == "Star" ? "Star the repo on GitHub" : "Sponsor development")
    }
}
