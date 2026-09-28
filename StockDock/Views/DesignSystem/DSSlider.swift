import SwiftUI

struct DSSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var width: CGFloat = 160

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        // Clamp so a value persisted outside the current range can't push the
        // knob/fill off the track.
        return min(max(CGFloat((value - range.lowerBound) / span), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knob: CGFloat = 16
            let travel = max(w - knob, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(DS.inkTertiary.opacity(0.22)).frame(height: 4)
                Capsule().fill(DS.brand).frame(width: fraction * travel + knob / 2, height: 4)
                Circle().fill(.white)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(DS.brand, lineWidth: 2))
                    .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
                    .offset(x: fraction * travel)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max((g.location.x - knob / 2) / travel, 0), 1)
                        let span = range.upperBound - range.lowerBound
                        let raw = range.lowerBound + Double(f) * span
                        let stepped = step > 0 ? (raw / step).rounded() * step : raw
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(width: width, height: 16)
    }
}
