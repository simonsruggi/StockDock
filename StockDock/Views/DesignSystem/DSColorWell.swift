import SwiftUI

/// A custom color well: a swatch that opens a DS popover with a
/// saturation/brightness field and a hue slider — no system color panel.
struct DSColorWell: View {
    @Binding var color: Color
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 40, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            HSBColorPicker(color: $color).padding(12).frame(width: 236)
        }
    }
}
