import SwiftUI

/// The window ground: warm paper with a whisper of brand emerald in one corner.
struct AppBackground: View {
    var body: some View {
        ZStack {
            DS.ground
            RadialGradient(colors: [DS.brand.opacity(0.045), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }
}
