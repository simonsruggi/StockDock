import AppKit
import SwiftUI

extension PortfolioWindowView {
    /// Takes the window to a search result.
    func handleSearch(_ target: SearchTarget) {
        showPalette = false
        switch target {
        case .go(.home):
            selection = storageService.showNewsTab ? .home : .watchlist
        case .go(.watchlist):
            selection = .watchlist
        case .go(.portfolios):
            selection = .portfoliosAll
        case .go(.settings):
            selection = .settings
        case .portfolio(let id), .holding(_, let id):
            selection = .portfolio(id)
        case .setting(let key):
            selection = .settings
            router.highlight(setting: windowKey(for: SettingsCatalog.visibleKey(key, storage: storageService)))
        case .symbol(let symbol):
            selection = .watchlist
            router.detailSymbol = symbol
        case .addSymbol(let symbol):
            storageService.addToWatchlist(symbol)
            Task { await stockService.refreshAll(storageService: storageService) }
            selection = .watchlist
            router.detailSymbol = symbol
        case .action(.refresh):
            Task { await stockService.refreshAll(storageService: storageService) }
        case .action(.newPortfolio):
            showNewPortfolio = true
        case .action(.checkForUpdates):
            updaterViewModel.checkForUpdates()
        case .action(.openWindow):
            break
        }
    }

    /// The desktop shows alerts and portfolio notifications only when there are some.
    private func windowKey(for key: String) -> String {
        switch key {
        case "priceAlerts" where storageService.alerts.isEmpty: return "webhook"
        case "portfolioNotifications" where !storageService.portfolios.contains(where: { !storageService.notifications(for: $0.id).isEmpty }):
            return "webhook"
        default: return key
        }
    }
}
