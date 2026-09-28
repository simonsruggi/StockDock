import SwiftUI
import AppKit

struct HSBColorPicker: View {
    @Binding var color: Color
    @State private var hue: Double = 0
    @State private var sat: Double = 1
    @State private var bri: Double = 1

    var body: some View {
        VStack(spacing: 12) {
            // Saturation (x) × brightness (y) field
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    Rectangle().fill(LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                                                    startPoint: .leading, endPoint: .trailing))
                    Rectangle().fill(LinearGradient(colors: [.clear, .black],
                                                    startPoint: .top, endPoint: .bottom))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    Circle().stroke(.white, lineWidth: 2).shadow(radius: 1)
                        .frame(width: 14, height: 14)
                        .position(x: sat * w, y: (1 - bri) * h)
                )
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    guard w > 0, h > 0 else { return }
                    sat = min(max(g.location.x / w, 0), 1)
                    bri = 1 - min(max(g.location.y / h, 0), 1)
                    push()
                })
            }
            .frame(height: 130)

            // Hue slider
            GeometryReader { geo in
                let w = geo.size.width
                Capsule()
                    .fill(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6.0).map {
                        Color(hue: $0, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                    .overlay(
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(DS.hairline))
                            .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                            .position(x: hue * (w - 16) + 8, y: 6)
                    )
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        guard w > 16 else { return }
                        hue = min(max((g.location.x - 8) / (w - 16), 0), 1)
                        push()
                    })
            }
            .frame(height: 16)
        }
        .onAppear(perform: pull)
    }

    private func push() { color = Color(hue: hue, saturation: sat, brightness: bri) }

    private func pull() {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = Double(h); sat = Double(s); bri = Double(b)
    }
}
