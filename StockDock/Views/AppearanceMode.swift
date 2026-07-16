import SwiftUI

/// Issue #11: user-facing appearance control. The 1.9.0 redesign pinned the app
/// to the light appearance; this restores the choice. `System` follows the OS,
/// `Light`/`Dark` force a scheme. Persisted as its `rawValue` in StorageService.
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    /// Shipped default. Kept `light` so users happy with the 1.9.x look see no
    /// change unless they opt in — while anyone who wants dark now can pick it.
    static let `default`: AppearanceMode = .light

    /// SwiftUI scheme to apply via `.preferredColorScheme`. `nil` = follow the OS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Settings label.
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}
