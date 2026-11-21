import Foundation

/// Hands a chosen result to the surface that asked for it (popover or window)
/// and carries the follow-up the destination view picks up once it appears:
/// a setting row to flash, a watchlist filter, a symbol detail to open.
@MainActor
final class SearchRouter: ObservableObject {
    static let shared = SearchRouter()

    enum Surface { case popover, window }

    struct Request: Equatable {
        let id = UUID()
        let surface: Surface
        let target: SearchTarget
    }

    @Published var request: Request?
    /// `SettingsCatalog` key of the row to scroll to and flash.
    @Published var highlightedSetting: String?
    /// Popover watchlist: text to filter by.
    @Published var watchlistFilter: String?
    /// Popover portfolios: text to filter by.
    @Published var portfolioFilter: String?
    /// Desktop watchlist: symbol whose detail sheet to open.
    @Published var detailSymbol: String?
    /// Popover portfolios: open the new-portfolio prompt.
    @Published var newPortfolioRequested = false

    private init() {}

    func send(_ target: SearchTarget, from surface: Surface) {
        request = Request(surface: surface, target: target)
    }

    /// Opens the setting's category in the popover and flashes its row for a moment.
    func highlight(setting key: String) {
        if let group = SettingsCatalog.entry(key)?.group {
            UserDefaults.standard.set(true, forKey: "settings.group.\(group)")
        }
        highlightedSetting = key
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if highlightedSetting == key { highlightedSetting = nil }
        }
    }
}
