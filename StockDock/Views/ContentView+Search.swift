import AppKit
import SwiftUI

extension ContentView {
    /// Takes the popover to a search result.
    func handleSearch(_ target: SearchTarget) {
        searchFocused = false
        switch target {
        case .go(let destination):
            selectedTab = Self.tab(for: destination, showNews: storageService.showNewsTab)
        case .portfolio(let id):
            router.portfolioFilter = storageService.portfolios.first { $0.id == id }?.name
            selectedTab = .portfolios
        case .setting(let key):
            router.highlight(setting: SettingsCatalog.visibleKey(key, storage: storageService))
            selectedTab = .settings
        case .symbol(let symbol):
            router.watchlistFilter = symbol
            selectedTab = .watchlist
        case .holding(let symbol, _):
            router.portfolioFilter = symbol
            selectedTab = .portfolios
        case .addSymbol(let symbol):
            storageService.addToWatchlist(symbol)
            Task { await stockService.refreshAll(storageService: storageService) }
            router.watchlistFilter = symbol
            selectedTab = .watchlist
        case .action(.refresh):
            Task { await stockService.refreshAll(storageService: storageService) }
        case .action(.newPortfolio):
            router.newPortfolioRequested = true
            selectedTab = .portfolios
        case .action(.checkForUpdates):
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            updaterViewModel.checkForUpdates()
        case .action(.openWindow):
            openWindowAction()
        }
    }

    static func tab(for destination: SearchTarget.Destination, showNews: Bool) -> Tab {
        switch destination {
        case .home: return showNews ? .home : .watchlist
        case .watchlist: return .watchlist
        case .portfolios: return .portfolios
        case .settings: return .settings
        }
    }
}
