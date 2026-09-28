import SwiftUI

/// Shared outline tag (SHORT, leverage, …) — 9.5pt, the app's smallest size.
struct Tag: View {
    let text: String
    var color: Color = DS.brand
    var body: some View {
        Text(LocalizedStringKey(text))
            .font(DS.micro)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(color.opacity(0.45), lineWidth: 1))
    }
}
