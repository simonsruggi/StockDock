import SwiftUI

struct ChangePill: View {
    let value: Double
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: value >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text(text).font(.inter(11.5, weight: .semibold, relativeTo: .caption).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(DS.pnlColor(value))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(value >= 0 ? DS.upSoft : DS.downSoft))
        // See StatTile: price-driven, so it must settle between ticks.
        .animation(DS.tick, value: text)
    }
}
