import SwiftUI

struct DSSpinner: View {
    var size: CGFloat = 16
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0.1, to: 0.9)
            .stroke(DS.brand, style: StrokeStyle(lineWidth: max(size * 0.14, 1.5), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}
