import SwiftUI
import AppKit

extension NSColor {
    /// Parses "#RRGGBB" / "RRGGBB" (and optional alpha "#RRGGBBAA"). Returns nil if invalid.
    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// "#RRGGBB" in the sRGB space (alpha dropped; menu bar text is always opaque).
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension Color {
    /// SwiftUI Color from a hex string, falling back to the system label color.
    static func fromHex(_ hex: String) -> Color {
        Color(nsColor: NSColor(hexString: hex) ?? .labelColor)
    }

    /// "#RRGGBB" representation of this color.
    var hexString: String { NSColor(self).hexString }
}

extension StorageService {
    /// Resolved gain color for the menu bar (system green until a custom one is set).
    var gainColor: NSColor {
        gainColorHex.isEmpty ? .systemGreen : (NSColor(hexString: gainColorHex) ?? .systemGreen)
    }
    /// Resolved loss color for the menu bar (system red until a custom one is set).
    var lossColor: NSColor {
        lossColorHex.isEmpty ? .systemRed : (NSColor(hexString: lossColorHex) ?? .systemRed)
    }
}
