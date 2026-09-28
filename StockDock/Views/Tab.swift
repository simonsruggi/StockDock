import Foundation

enum Tab: String, CaseIterable {
    case home = "Home"
    case watchlist = "Watchlist"
    case portfolios = "Portfolios"
    case settings = "Settings"
}

extension Tab {
    var icon: String {
        switch self {
        case .home: return "newspaper"
        case .watchlist: return "list.bullet"
        case .portfolios: return "briefcase"
        case .settings: return "gear"
        }
    }

    /// Issue #11: the tabs that actually render, in order. The Home/News tab is
    /// opt-out — when hidden, Watchlist leads. Single source of truth so the tab
    /// bar, the content switch and the restored-selection logic never disagree.
    static func visible(showNews: Bool) -> [Tab] {
        let all: [Tab] = [.home, .watchlist, .portfolios, .settings]
        return showNews ? all : all.filter { $0 != .home }
    }

    /// Resolve a persisted tab against the current visibility: a stored selection
    /// that's now hidden (e.g. "Home" after News was turned off) falls back to the
    /// first visible tab so the user is never stranded on a blank tab.
    static func resolve(stored: String, showNews: Bool) -> Tab {
        let tabs = visible(showNews: showNews)
        if let t = Tab(rawValue: stored), tabs.contains(t) { return t }
        return tabs.first ?? .watchlist
    }
}
