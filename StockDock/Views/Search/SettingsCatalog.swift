import Foundation

/// Every searchable setting: its row title (the same localization key the row
/// shows), the popover category it lives in, and extra words people type for it.
enum SettingsCatalog {
    struct Entry {
        let key: String
        let title: String
        /// `SettingsView` group key (`settings.group.<group>`).
        let group: String
        let keywords: [String]
    }

    static let entries: [Entry] = [
        Entry(key: "language", title: "Language", group: "general", keywords: ["lingua", "idioma", "sprache", "langue", "translation"]),
        Entry(key: "theme", title: "Theme", group: "general", keywords: ["dark mode", "light mode", "appearance", "tema", "scuro", "chiaro"]),
        Entry(key: "font", title: "Font", group: "general", keywords: ["typeface", "carattere", "inter"]),
        Entry(key: "textSize", title: "Text size", group: "general", keywords: ["font size", "zoom", "bigger", "smaller", "dimensione testo"]),
        Entry(key: "newsTab", title: "Show News tab", group: "general", keywords: ["news", "home", "notizie"]),
        Entry(key: "priceCurrency", title: "Stock price currency", group: "currency", keywords: ["currency", "valuta", "usd", "eur", "dollar", "euro"]),
        Entry(key: "portfolioCurrency", title: "Portfolio currency", group: "currency", keywords: ["currency", "valuta", "totals", "eur", "usd"]),
        Entry(key: "advanced", title: "Short positions & leverage", group: "positions", keywords: ["short", "leverage", "leva", "margin", "cfd"]),
        Entry(key: "tax", title: "Tax on gains", group: "positions", keywords: ["tax", "tasse", "capital gain", "26%", "net"]),
        Entry(key: "weights", title: "Weights based on", group: "positions", keywords: ["weight", "allocation", "peso", "allocazione"]),
        Entry(key: "extendedHours", title: "Extended hours (Pre/Post)", group: "positions", keywords: ["pre-market", "after hours", "premarket", "postmarket"]),
        Entry(key: "allHours", title: "Overnight & weekends (Hyperliquid)", group: "positions", keywords: ["24/7", "overnight", "weekend", "hyperliquid", "notte"]),
        Entry(key: "companyName", title: "Company name", group: "watchlist", keywords: ["name", "nome"]),
        Entry(key: "dayRange", title: "Day range (low – high)", group: "watchlist", keywords: ["high", "low", "range", "minimo", "massimo"]),
        Entry(key: "week52", title: "52-week range bar", group: "watchlist", keywords: ["52 week", "year range", "52 settimane"]),
        Entry(key: "absoluteChange", title: "Absolute change value", group: "watchlist", keywords: ["change", "variazione"]),
        Entry(key: "menuBarDisplay", title: "Display", group: "menubar", keywords: ["menu bar", "status bar", "barra", "ticker", "show"]),
        Entry(key: "tickerName", title: "Show name instead of symbol", group: "menubar", keywords: ["ticker", "name"]),
        Entry(key: "tickerOrder", title: "Ticker order", group: "menubar", keywords: ["ticker", "order", "sort", "ordine"]),
        Entry(key: "hidePercent", title: "Hide percentage change", group: "menubar", keywords: ["percent", "%", "percentuale"]),
        Entry(key: "systemColor", title: "Use system color in the menu bar", group: "menubar", keywords: ["color", "colour", "colore", "wallpaper"]),
        Entry(key: "percentDecimals", title: "Percentage decimals", group: "menubar", keywords: ["decimals", "decimali", "digits", "precision"]),
        Entry(key: "valueDecimals", title: "Value decimals", group: "menubar", keywords: ["decimals", "decimali", "digits", "precision"]),
        Entry(key: "gainColor", title: "Gain color", group: "menubar", keywords: ["green", "verde", "color", "colore"]),
        Entry(key: "lossColor", title: "Loss color", group: "menubar", keywords: ["red", "rosso", "color", "colore"]),
        Entry(key: "webhook", title: "Mirror to a Discord/Slack webhook", group: "notifications", keywords: ["discord", "slack", "webhook", "notifications", "notifiche"]),
        Entry(key: "priceAlerts", title: "Price alerts", group: "notifications", keywords: ["alert", "avvisi", "allarmi", "notifications"]),
        Entry(key: "portfolioNotifications", title: "Portfolio notifications", group: "notifications", keywords: ["notifications", "notifiche", "alert"]),
        Entry(key: "updates", title: "Updates", group: "about", keywords: ["update", "aggiornamenti", "version", "sparkle"]),
        Entry(key: "support", title: "Support StockDock", group: "about", keywords: ["sponsor", "star", "github", "donate"]),
        Entry(key: "reset", title: "Reset", group: "about", keywords: ["reset", "defaults", "ripristina"]),
    ]

    static func entry(_ key: String) -> Entry? { entries.first { $0.key == key } }

    /// Rows shown only under another setting fall back to the one that reveals them.
    @MainActor static func visibleKey(_ key: String, storage: StorageService) -> String {
        switch key {
        case "allHours" where !storage.showExtendedHours:
            return "extendedHours"
        case "tickerName", "tickerOrder" where storage.menuBarDisplay != "ticker" && storage.menuBarDisplay != "tickerPortfolio":
            return "menuBarDisplay"
        default:
            return key
        }
    }
}
