import SwiftUI

/// A faint decorative market-curve stroked in hairline — used behind empty chart
/// states so the placeholder evokes the chart to come.
struct DecorativeCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0, y: h * 0.62))
        p.addCurve(to: CGPoint(x: w * 0.34, y: h * 0.48),
                   control1: CGPoint(x: w * 0.12, y: h * 0.70),
                   control2: CGPoint(x: w * 0.24, y: h * 0.38))
        p.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.55),
                   control1: CGPoint(x: w * 0.46, y: h * 0.60),
                   control2: CGPoint(x: w * 0.57, y: h * 0.66))
        p.addCurve(to: CGPoint(x: w, y: h * 0.30),
                   control1: CGPoint(x: w * 0.80, y: h * 0.42),
                   control2: CGPoint(x: w * 0.91, y: h * 0.34))
        return p
    }
}
