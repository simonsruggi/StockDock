import SwiftUI

struct StatTile: View {
    let label: String
    let value: String
    var caption: String? = nil
    var captionTint: Color = DS.inkTertiary
    var valueTint: Color = DS.ink
    var help: String? = nil
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(label)
            Text(value)
                .font(DS.figureLG)
                .foregroundStyle(valueTint)
                .contentTransition(.numericText())
                // Short, NOT a spring: live prices flush once per second, and a
                // spring at response 0.45 settles in ~1s — so the tile animated
                // continuously, and every frame re-rasterized the card's shadow
                // blur on the CPU. `DS.tick` finishes well inside the tick gap.
                .animation(DS.tick, value: value)
                .lineLimit(1).minimumScaleFactor(0.6)
            // Always reserve the caption line so every tile is the same height.
            Text(caption ?? " ")
                .font(.inter(10.5, relativeTo: .caption2).monospacedDigit())
                .foregroundStyle(captionTint)
                .opacity(caption == nil ? 0 : 1)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(cornerRadius: 12, elevated: hover)
        .scaleEffect(hover ? 1.012 : 1)
        .animation(.easeOut(duration: 0.16), value: hover)
        .onHover { hover = $0 }
        .help(help ?? label)
    }
}
