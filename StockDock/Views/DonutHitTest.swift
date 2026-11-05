import CoreGraphics

/// Which donut slice sits under a point. Swift Charts draws sectors clockwise
/// from 12 o'clock in data order, so the angle maps onto cumulative fractions.
enum DonutHitTest {
    static func slice(at point: CGPoint, in size: CGSize, innerRatio: CGFloat,
                      fractions: [(id: String, fraction: Double)]) -> String? {
        let dx = point.x - size.width / 2
        let dy = point.y - size.height / 2
        let radius = min(size.width, size.height) / 2
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance <= radius, distance >= radius * innerRatio else { return nil }
        var angle = atan2(dx, -dy) / (2 * .pi)
        if angle < 0 { angle += 1 }
        var start = 0.0
        for f in fractions {
            start += f.fraction
            if Double(angle) < start { return f.id }
        }
        return fractions.last?.id
    }
}
