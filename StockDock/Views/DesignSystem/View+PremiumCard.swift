import SwiftUI

extension View {
    /// The card surface with the app's 3-level elevation: E1 resting (soft dual
    /// shadow) or E2 lifted (`elevated: true`, for hover on clickable cards).
    /// Never add extra `.shadow` after this — it would blur the border overlay.
    func premiumCard(cornerRadius: CGFloat = 16, elevated: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DS.card)
                    .shadow(color: .black.opacity(elevated ? 0.08 : 0.05),
                            radius: elevated ? 24 : 18, x: 0, y: elevated ? 10 : 8)
                    .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.18), value: elevated)
    }
}
