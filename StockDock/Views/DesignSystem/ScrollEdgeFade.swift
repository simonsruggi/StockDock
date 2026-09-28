import SwiftUI

/// A top overlay that dissolves scrolled content under the transparent titlebar.
struct ScrollEdgeFade: View {
    var height: CGFloat = 64
    var body: some View {
        // Follows the appearance so the scrolled-content fade matches the window
        // ground in both light and dark (was pinned to the light paper color).
        LinearGradient(colors: [DS.ground, .clear],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .allowsHitTesting(false)
    }
}
