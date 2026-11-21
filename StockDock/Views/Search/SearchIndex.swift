import Foundation

/// Builds the local results — actions, settings, watchlist, positions,
/// portfolios — for a query. Market results come from Yahoo in `UniversalSearchModel`.
@MainActor
enum SearchIndex {
    static let perSection = 5

    struct ActionEntry {
        let title: String
        let icon: String
        let keywords: [String]
        let target: SearchTarget
    }

    static func actions(inWindow: Bool, showNews: Bool) -> [ActionEntry] {
        var list: [ActionEntry] = []
        if showNews { list.append(ActionEntry(title: "Home", icon: "newspaper", keywords: ["news", "notizie"], target: .go(.home))) }
        list += [
            ActionEntry(title: "Watchlist", icon: "list.bullet", keywords: ["stocks", "titoli", "azioni"], target: .go(.watchlist)),
            ActionEntry(title: "Portfolios", icon: "briefcase", keywords: ["portafogli", "positions", "posizioni"], target: .go(.portfolios)),
            ActionEntry(title: "Settings", icon: "gearshape", keywords: ["preferences", "impostazioni", "options"], target: .go(.settings)),
            ActionEntry(title: "Refresh prices", icon: "arrow.clockwise", keywords: ["reload", "update", "aggiorna"], target: .action(.refresh)),
            ActionEntry(title: "New Portfolio", icon: "plus.rectangle.on.folder", keywords: ["create", "add", "nuovo", "crea"], target: .action(.newPortfolio)),
            ActionEntry(title: "Check for Updates…", icon: "arrow.down.circle", keywords: ["version", "upgrade", "aggiornamenti"], target: .action(.checkForUpdates)),
        ]
        if !inWindow {
            list.append(ActionEntry(title: "Open StockDock window", icon: "macwindow", keywords: ["desktop", "window", "finestra"], target: .action(.openWindow)))
        }
        return list
    }

    static func results(for query: String, storage: StorageService, stocks: StockService, inWindow: Bool) -> [SearchItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = storage.appLanguage
        var items: [SearchItem] = []

        for (index, a) in actions(inWindow: inWindow, showNews: storage.showNewsTab).enumerated() {
            let title = localized(a.title, language)
            // An empty query lists the actions as a starting menu, in their natural order.
            let score = q.isEmpty ? 100 - index : SearchMatcher.score(q, fields: [title, a.title] + a.keywords)
            if let score {
                items.append(SearchItem(id: "action.\(index)", section: .actions, title: a.title, icon: a.icon,
                                        target: a.target, score: score, localizedTitle: true))
            }
        }
        guard !q.isEmpty else { return items }

        for entry in SettingsCatalog.entries {
            let title = localized(entry.title, language)
            if let score = SearchMatcher.score(q, fields: [title, entry.title] + entry.keywords) {
                items.append(SearchItem(id: "setting.\(entry.key)", section: .settings, title: entry.title,
                                        subtitle: localized(groupTitle(entry.group), language), icon: "gearshape",
                                        target: .setting(entry.key), score: score, localizedTitle: true))
            }
        }

        for symbol in storage.watchlist {
            let name = stocks.quotes[symbol]?.name ?? ""
            let alias = storage.alias(for: symbol)
            if let score = SearchMatcher.score(q, fields: [symbol, alias, name]) {
                items.append(SearchItem(id: "watch.\(symbol)", section: .watchlist, title: alias.isEmpty ? symbol : alias,
                                        subtitle: alias.isEmpty ? name : symbol, icon: "chart.line.uptrend.xyaxis",
                                        target: .symbol(symbol), score: score))
            }
        }

        for portfolio in storage.portfolios {
            if let score = SearchMatcher.score(q, fields: [portfolio.name]) {
                items.append(SearchItem(id: "portfolio.\(portfolio.id)", section: .portfolios, title: portfolio.name,
                                        subtitle: Array(NSOrderedSet(array: portfolio.holdings.map(\.symbol))).compactMap { $0 as? String }.prefix(4).joined(separator: ", "),
                                        icon: "briefcase",
                                        target: .portfolio(portfolio.id), score: score))
            }
            // Lots of the same symbol are one position per portfolio.
            var seen = Set<String>()
            for holding in portfolio.holdings where seen.insert(holding.symbol).inserted {
                let name = stocks.quotes[holding.symbol]?.name ?? ""
                if let score = SearchMatcher.score(q, fields: [holding.symbol, name, portfolio.name]) {
                    let shares = portfolio.holdings.filter { $0.symbol == holding.symbol }.reduce(0) { $0 + $1.quantity }
                    items.append(SearchItem(id: "holding.\(portfolio.id).\(holding.symbol)", section: .positions,
                                            title: holding.symbol,
                                            subtitle: "\(portfolio.name) · \(shares.formatted(.number.precision(.fractionLength(0...4)))) sh",
                                            icon: "chart.pie", target: .holding(symbol: holding.symbol, portfolioId: portfolio.id),
                                            score: score))
                }
            }
        }
        return ranked(items)
    }

    /// Best first inside each section, capped, sections in their fixed order.
    static func ranked(_ items: [SearchItem]) -> [SearchItem] {
        SearchItem.Section.allCases.flatMap { section in
            items.filter { $0.section == section }.sorted { $0.score > $1.score }.prefix(perSection)
        }
    }

    static func groupTitle(_ group: String) -> String {
        switch group {
        case "general": return "General"
        case "currency": return "Currency"
        case "positions": return "Positions & Market"
        case "watchlist": return "Watchlist"
        case "menubar": return "Menu Bar"
        case "notifications": return "Notifications"
        default: return "About & Data"
        }
    }

    /// The key translated into the in-app language, so searching in Italian finds Italian labels.
    static func localized(_ key: String, _ language: String) -> String {
        guard language != "en", let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
