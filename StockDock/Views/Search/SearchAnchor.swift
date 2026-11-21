import SwiftUI

/// Marks a settings row as a search destination: gives it a scroll id and
/// flashes it when search lands on it.
struct SearchAnchor: ViewModifier {
    let key: String
    @ObservedObject private var router = SearchRouter.shared

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DS.brand.opacity(router.highlightedSetting == key ? 0.14 : 0))
                    .padding(.horizontal, -8)
            )
            .animation(.easeInOut(duration: 0.35), value: router.highlightedSetting)
            .id(Self.scrollID(key))
    }

    static func scrollID(_ key: String) -> String { "setting.\(key)" }
}

extension View {
    func searchAnchor(_ key: String) -> some View { modifier(SearchAnchor(key: key)) }
}
