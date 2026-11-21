import Foundation

/// One row of the search results.
struct SearchItem: Identifiable, Hashable {
    enum Section: Int, CaseIterable {
        case actions, settings, watchlist, positions, portfolios, market

        var title: String {
            switch self {
            case .actions: return "Go to"
            case .settings: return "Settings"
            case .watchlist: return "Watchlist"
            case .positions: return "Positions"
            case .portfolios: return "Portfolios"
            case .market: return "Add to watchlist"
            }
        }
    }

    let id: String
    let section: Section
    let title: String
    var subtitle: String = ""
    let icon: String
    let target: SearchTarget
    var score: Int = 0
    /// Title is a localization key (settings, actions) rather than data (a ticker, a name).
    var localizedTitle = false
}
