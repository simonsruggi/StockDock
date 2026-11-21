import Foundation

/// Where a search result takes you. The popover and the desktop window each
/// resolve it into their own navigation (see `SearchRouter`).
enum SearchTarget: Hashable {
    enum Destination: Hashable { case home, watchlist, portfolios, settings }
    enum Action: Hashable { case refresh, newPortfolio, checkForUpdates, openWindow }

    case go(Destination)
    case portfolio(UUID)
    /// A row of Settings, by its `SettingsCatalog` key.
    case setting(String)
    /// A symbol already in the watchlist.
    case symbol(String)
    /// A position: the symbol inside one portfolio.
    case holding(symbol: String, portfolioId: UUID)
    /// A market result not in the watchlist yet: added, then shown.
    case addSymbol(String)
    case action(Action)
}
