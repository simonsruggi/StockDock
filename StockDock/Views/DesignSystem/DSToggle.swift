import SwiftUI

struct DSToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? DS.brand : DS.inkTertiary.opacity(0.28))
                .frame(width: 38, height: 22)
                .overlay(alignment: .leading) {
                    Circle().fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(2)
                        .offset(x: isOn ? 16 : 0)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
