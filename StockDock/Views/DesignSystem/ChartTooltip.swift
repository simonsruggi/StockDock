import SwiftUI

/// Floating value tooltip shown when hovering a chart line.
struct ChartTooltip: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(DS.micro).foregroundStyle(DS.inkTertiary)
            Text(value).font(.inter(12, weight: .semibold, relativeTo: .body).monospacedDigit()).foregroundStyle(tint)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.card)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DS.hairline))
        .fixedSize()
    }
}
