import SwiftUI
import AppKit

/// The StockDock brand mark: the official app icon (the one shipped in the last
/// release), used everywhere. Falls back to a designed emerald mark only if the
/// icon can't be loaded (should never happen in the bundled app).
struct BrandMark: View {
    var size: CGFloat = 28

    /// Loaded once from the app's bundled icon (works in dev and release).
    private static let appIcon: NSImage? = {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let sys = NSApp.applicationIconImage
        return (sys?.size.width ?? 0) > 0 ? sys : nil
    }()

    var body: some View {
        Group {
            if let icon = Self.appIcon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                fallbackMark
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }

    private var fallbackMark: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [DS.up, DS.brand, Color(red: 0.08, green: 0.33, blue: 0.30)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white))
    }
}
