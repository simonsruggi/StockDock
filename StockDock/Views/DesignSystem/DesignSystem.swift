import SwiftUI
import AppKit

/// Design tokens for the StockDock desktop window — the "private banking" light
/// editorial system: warm paper ground, white card stock, one sober emerald,
/// generous whitespace, immaculate numeric typography. The window is pinned to
/// the light appearance; dark branches are kept only as a safety net for sheets
/// that may inherit the system appearance.
enum DS {
    // MARK: Surfaces
    /// Window/detail ground — warm paper.
    static let ground = dynamic(light: NSColor(red: 0.984, green: 0.980, blue: 0.969, alpha: 1),
                                dark: NSColor(white: 0.09, alpha: 1))
    /// Sidebar flat tint — a hair darker than the ground.
    static let sidebarBG = dynamic(light: NSColor(red: 0.957, green: 0.945, blue: 0.918, alpha: 1),
                                   dark: NSColor(white: 0.11, alpha: 1))
    /// Card stock.
    static let card = dynamic(light: .white, dark: NSColor(white: 0.13, alpha: 1))
    /// Inset wells, chart placeholders, thumbnails.
    static let cardAlt = dynamic(light: NSColor(red: 0.961, green: 0.949, blue: 0.925, alpha: 1),
                                 dark: NSColor(white: 0.17, alpha: 1))
    /// Borders and dividers — warm, near-invisible.
    static let hairline = dynamic(light: NSColor(red: 0.102, green: 0.090, blue: 0.059, alpha: 0.07),
                                  dark: NSColor(white: 1, alpha: 0.10))
    /// Chart gridlines. Deliberately heavier than `hairline`: a border only has
    /// to separate two filled surfaces, a gridline has to be readable on its own
    /// across an empty plot area (#14).
    static let chartGrid = dynamic(light: NSColor(red: 0.102, green: 0.090, blue: 0.059, alpha: 0.16),
                                   dark: NSColor(white: 1, alpha: 0.16))

    // MARK: Ink
    /// Warm near-black for display text.
    static let ink = dynamic(light: NSColor(red: 0.110, green: 0.102, blue: 0.082, alpha: 1),
                             dark: NSColor(white: 0.94, alpha: 1))
    /// Warm secondary gray (instead of the blue-ish system secondary).
    static let inkSecondary = dynamic(light: NSColor(red: 0.431, green: 0.416, blue: 0.376, alpha: 1),
                                      dark: NSColor(red: 0.64, green: 0.62, blue: 0.58, alpha: 1))
    /// Captions, placeholders, timestamps.
    static let inkTertiary = dynamic(light: NSColor(red: 0.608, green: 0.588, blue: 0.541, alpha: 1),
                                     dark: NSColor(red: 0.50, green: 0.485, blue: 0.45, alpha: 1))

    // MARK: Accents
    /// Brand emerald — selection, links, the mark.
    static let brand = Color(red: 0.110, green: 0.451, blue: 0.369)
    /// Gains — sober emerald (default when no custom gain color is set).
    static let upDefault = Color(red: 0.129, green: 0.522, blue: 0.400)
    /// Losses — muted terracotta (default when no custom loss color is set).
    static let downDefault = Color(red: 0.761, green: 0.290, blue: 0.267)

    /// Gain color used across the whole app. Honors the user's custom gain color
    /// (Settings → Colors) when set, otherwise the emerald default. Views that
    /// show P&L observe StorageService, so changing the color re-renders them.
    @MainActor static var up: Color {
        let s = StorageService.shared
        return s.gainColorHex.isEmpty ? upDefault : Color(nsColor: s.gainColor)
    }
    /// Loss color used across the whole app. Custom loss color when set, else the
    /// terracotta default.
    @MainActor static var down: Color {
        let s = StorageService.shared
        return s.lossColorHex.isEmpty ? downDefault : Color(nsColor: s.lossColor)
    }
    @MainActor static var upSoft: Color { up.opacity(0.10) }
    @MainActor static var downSoft: Color { down.opacity(0.10) }
    /// The one reserved luxury accent: FEATURED label and concentration warnings.
    static let gold = Color(red: 0.722, green: 0.573, blue: 0.247)

    /// Categorical palette for allocation / series — muted, magazine-like.
    static let palette: [Color] = [
        Color(red: 0.13, green: 0.45, blue: 0.37),
        Color(red: 0.72, green: 0.58, blue: 0.36),
        Color(red: 0.35, green: 0.46, blue: 0.62),
        Color(red: 0.55, green: 0.42, blue: 0.55),
        Color(red: 0.76, green: 0.44, blue: 0.36),
        Color(red: 0.40, green: 0.58, blue: 0.55),
        Color(red: 0.62, green: 0.55, blue: 0.42),
        Color(red: 0.50, green: 0.52, blue: 0.56),
    ]

    @MainActor static func pnlColor(_ v: Double) -> Color { v >= 0 ? up : down }

    // MARK: Type scale (Inter everywhere; tracking applied at call sites on ≥24pt)
    /// Hero value only. Pair with `.tracking(-0.5)`.
    static let display = Font.inter(44, weight: .bold, relativeTo: .largeTitle).monospacedDigit()
    /// Page titles, holding symbol. Pair with `.tracking(-0.3)`.
    static let titleXL = Font.inter(24, weight: .bold, relativeTo: .title)
    /// Card feature headlines.
    static let title = Font.inter(17, weight: .semibold, relativeTo: .title3)
    static let body = Font.inter(13, relativeTo: .body)
    static let bodyStrong = Font.inter(13, weight: .semibold, relativeTo: .body)
    /// Table numbers.
    static let figure = Font.inter(13, weight: .medium, relativeTo: .body).monospacedDigit()
    /// Stat tile values.
    static let figureLG = Font.inter(22, weight: .semibold, relativeTo: .title2).monospacedDigit()
    static let caption = Font.inter(11, relativeTo: .caption)
    /// Uppercase section labels. Pair with `.tracking(0.8)`.
    static let label = Font.inter(10.5, weight: .semibold, relativeTo: .caption2)
    /// Timestamps, chips — the smallest legible size in the app.
    static let micro = Font.inter(9.5, weight: .medium, relativeTo: .caption2)

    // MARK: Metrics
    /// Page gutter around detail content.
    static let gutter: CGFloat = 32
    /// Gap between cards.
    static let gap: CGFloat = 20
    /// Card internal padding.
    static let pad: CGFloat = 20
    /// Detail content max width.
    static let contentMaxWidth: CGFloat = 1120
    /// Clearance under the transparent titlebar (traffic lights).
    static let titlebarClearance: CGFloat = 52

    // MARK: Motion
    /// Animation for anything driven by the live price feed.
    ///
    /// Ticks are flushed once per second, so a price animation MUST finish well
    /// inside that second. Springs (response 0.4–0.5) settle in ~1s, which left
    /// SwiftUI interpolating without interruption — and because these values sit
    /// inside shadowed cards, every interpolated frame re-rasterized a gaussian
    /// blur on the CPU (vImage), pinning the app near 70% CPU all session.
    /// Keep any price-driven animation at or below this duration.
    static let tick: Animation = .easeOut(duration: 0.18)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: .init(name: nil) { $0.isDarkMode ? dark : light })
    }
}

extension NSAppearance {
    fileprivate var isDarkMode: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}
