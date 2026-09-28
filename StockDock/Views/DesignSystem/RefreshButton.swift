import SwiftUI

/// Ghost refresh control whose glyph rotates while a refresh is in flight —
/// never a spinner overlay.
struct RefreshButton: View {
    let isLoading: Bool
    let action: () -> Void
    @State private var spinning = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.inkSecondary)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                           value: spinning)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onChange(of: isLoading) { _, loading in spinning = loading }
        .help("Refresh quotes")
    }
}
