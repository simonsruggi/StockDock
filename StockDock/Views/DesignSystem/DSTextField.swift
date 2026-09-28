import SwiftUI

/// A DS-styled text field with its own emerald focus ring.
struct DSTextField: View {
    var placeholder: String
    @Binding var text: String
    var mono: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? DS.figure : DS.body)
            .foregroundStyle(DS.ink)
            .focused($focused)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.cardAlt))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? DS.brand : DS.hairline, lineWidth: focused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
