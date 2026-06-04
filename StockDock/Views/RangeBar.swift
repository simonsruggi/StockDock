import SwiftUI

/// A thin horizontal bar showing where the current price sits within the
/// 52-week low…high range. `position` is 0 (low) … 1 (high).
struct RangeBar: View {
    let position: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(height: 3)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .offset(x: CGFloat(min(max(position, 0), 1)) * (geo.size.width - 6))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 6)
    }
}
