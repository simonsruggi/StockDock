import Foundation

@MainActor
class StorageService: ObservableObject {
    static let shared = StorageService()

    @Published var watchlist: [String] = [] {
        didSet { scheduleSave() }
    }

    @Published var portfolios: [Portfolio] = [] {
        didSet { scheduleSave() }
    }

    @Published var preferredCurrency: String = "EUR" {
        didSet { scheduleSave() }
    }

    @Published var stockPriceCurrency: String = "" {
        didSet { scheduleSave() }
    }

    @Published var showExtendedHours: Bool = true {
        didSet { scheduleSave() }
    }

    // MARK: - Watchlist row display toggles
    @Published var showCompanyName: Bool = true {
        didSet { scheduleSave() }
    }
    @Published var showDayRange: Bool = true {
        didSet { scheduleSave() }
    }
    @Published var show52WeekBar: Bool = true {
        didSet { scheduleSave() }
    }
    @Published var showAbsoluteChange: Bool = true {
        didSet { scheduleSave() }
    }

    // MARK: - Appearance & tabs (issue #11)
    /// "system" | "light" | "dark". The 1.9.0 redesign forced light; this restores
    /// the choice. Read through `appearanceMode` for the typed value.
    @Published var appearanceRaw: String = AppearanceMode.default.rawValue {
        didSet { scheduleSave() }
    }
    /// Show the Home/News tab. Off = the tab is hidden entirely (no fetching, no
    /// tab), for users who want just their watchlist and portfolio.
    @Published var showNewsTab: Bool = true {
        didSet { scheduleSave() }
    }

    /// Typed appearance preference, tolerant of unknown persisted values.
    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .default }
        set { appearanceRaw = newValue.rawValue }
    }

    /// What to display in the menu bar: "pnl", "totalValue", "icon"
    @Published var menuBarDisplay: String = "pnl" {
        didSet { scheduleSave() }
    }

    // MARK: - Menu bar colors (issue #7.1)
    /// Hex color for gains/up moves. Empty = use the system green (dynamic).
    @Published var gainColorHex: String = "" {
        didSet { scheduleSave() }
    }
    /// Hex color for losses/down moves. Empty = use the system red (dynamic).
    @Published var lossColorHex: String = "" {
        didSet { scheduleSave() }
    }
    /// When true, the menu bar ignores gain/loss colors and uses the system label
    /// color (always readable on any background; direction stays in the +/- and ▲▼).
    @Published var menuBarUseSystemColor: Bool = false {
        didSet { scheduleSave() }
    }

    /// Issue #7.4 / #10: number of decimal places shown for percentages (0–4),
    /// everywhere a % appears (menu bar, watchlist, portfolios). Clamped on set.
    @Published var percentDecimals: Int = 1 {
        didSet {
            let clamped = min(max(percentDecimals, 0), 4)
            if clamped != percentDecimals { percentDecimals = clamped; return }
            scheduleSave()
        }
    }

    /// Issue #10: decimal places for *values* — prices and currency amounts.
    /// -1 = Auto (smart per #10: forex/sub-dollar get more precision, amounts use 2);
    /// 0–4 = force that many decimals everywhere (prices AND amounts).
    @Published var valueDecimals: Int = -1 {
        didSet {
            let clamped = min(max(valueDecimals, -1), 4)
            if clamped != valueDecimals { valueDecimals = clamped; return }
            scheduleSave()
        }
    }

    /// Price decimals honoring the manual override; Auto (-1) falls back to the
    /// smart per-symbol logic.
    func resolvedPriceDecimals(symbol: String, price: Double) -> Int {
        valueDecimals >= 0 ? valueDecimals : StorageService.priceDecimals(symbol: symbol, price: price)
    }

    /// Decimals for currency amounts (totals, P&L, position values); Auto (-1) = 2.
    var amountDecimals: Int { valueDecimals >= 0 ? valueDecimals : 2 }

    /// Issue #10: hide the percentage change in the menu bar (ticker/recap modes
    /// show just price / value). Off by default.
    @Published var menuBarHidePercent: Bool = false {
        didSet { scheduleSave() }
    }

    /// Unlocks short positions (negative quantity) and per-holding leverage in
    /// the add/edit holding sheets. Off by default to keep the common long-only
    /// flow simple.
    @Published var advancedPositions: Bool = false {
        didSet { scheduleSave() }
    }

    /// Issue #8.2: show the human-readable name (e.g. "S&P 500") instead of the
    /// raw symbol ("^GSPC") in the menu bar ticker. Off keeps the bar compact.
    @Published var tickerShowName: Bool = false {
        didSet { scheduleSave() }
    }

    /// Issue #8.1: order of the watchlist entries cycled in the menu bar ticker.
    /// "manual" = as added, "type" = grouped by asset class, "alpha" = alphabetical.
    @Published var watchlistSort: String = "manual" {
        didSet { scheduleSave() }
    }

    /// In-app UI language override (ISO code). Defaults to English.
    @Published var appLanguage: String = "en" {
        didSet { scheduleSave() }
    }

    /// Supported UI languages: (ISO code, native display name).
    static let supportedLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "简体中文"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("pt", "Português"),
    ]

    /// Maps symbol → ISIN for watchlist filtering
    @Published var isinMap: [String: String] = [:] {
        didSet { scheduleSave() }
    }

    /// Issue #8: maps symbol → Yahoo asset class ("EQUITY", "ETF", "INDEX",
    /// "FUTURE", …), uppercased. A symbol's type is stable, so it's resolved once
    /// (from search on add, or from the quote/chart feeds) and cached/persisted.
    @Published var symbolType: [String: String] = [:] {
        didSet { scheduleSave() }
    }

    /// Issue #12: maps symbol → user-chosen display name, for symbols whose ticker
    /// is unreadable in the menu bar ("CAD/USD" → "CAD", "^GSPC" → "S&P"). Empty
    /// or whitespace-only values are never stored — the entry is removed instead,
    /// so `alias(for:)` falling back to the symbol is the single "no alias" path.
    @Published var symbolAlias: [String: String] = [:] {
        didSet { scheduleSave() }
    }

    /// Sets or clears a symbol's custom display name. Passing an empty/blank name
    /// clears it.
    func setAlias(_ name: String, for symbol: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            symbolAlias.removeValue(forKey: symbol)
        } else {
            symbolAlias[symbol] = trimmed
        }
    }

    /// The user's custom name for a symbol, or "" when unset.
    func alias(for symbol: String) -> String { symbolAlias[symbol] ?? "" }

    /// What to show for a symbol: the custom name if set, otherwise `fallback`
    /// (the quote name or the raw symbol, depending on the caller's preference).
    func displayLabel(for symbol: String, fallback: String) -> String {
        let custom = alias(for: symbol)
        return custom.isEmpty ? fallback : custom
    }

    /// Records a symbol's asset class. Ignores empty values and no-ops when
    /// unchanged so it doesn't churn the save loop on every price refresh.
    func setType(_ type: String, for symbol: String) {
        let normalized = type.uppercased()
        guard !normalized.isEmpty, symbolType[symbol] != normalized else { return }
        symbolType[symbol] = normalized
    }

    /// Asset class for a symbol, or "" if not yet known.
    func type(for symbol: String) -> String { symbolType[symbol] ?? "" }

    /// One-shot price alerts.
    @Published var alerts: [PriceAlert] = [] {
        didSet { scheduleSave() }
    }

    /// Recurring portfolio notifications, keyed by portfolio id (uuidString).
    @Published var portfolioNotifications: [String: [PortfolioNotification]] = [:] {
        didSet { scheduleSave() }
    }

    /// Daily value/P&L snapshots for the Portfolio window's history chart, keyed
    /// by portfolio id (uuidString). Accumulates forward — see `PortfolioSnapshot`.
    @Published var portfolioSnapshots: [String: [PortfolioSnapshot]] = [:] {
        didSet { scheduleSave() }
    }

    /// Discord/Slack incoming webhook for mirroring notifications.
    @Published var discordWebhookURL: String = "" {
        didSet { scheduleSave() }
    }
    @Published var discordEnabled: Bool = false {
        didSet { scheduleSave() }
    }

    @Published var fontSizeLevel: Int = 9 {
        didSet {
            FontRegistration.sizeOffset = CGFloat(fontSizeLevel - 9)
            scheduleSave()
        }
    }

    @Published var fontFamily: String = "Inter Variable" {
        didSet {
            FontRegistration.familyName = fontFamily
            scheduleSave()
        }
    }

    func setISIN(_ isin: String, for symbol: String) {
        isinMap[symbol] = isin
    }

    var lastSelectedTab: String = "Watchlist"

    /// Issue #14: the chart range last picked by the user, restored next time
    /// instead of snapping back to a hard-coded default. Kept per chart kind
    /// because the useful default differs (a position vs the whole portfolio).
    /// Raw `ChartRange` values; "" or an unknown value = the view's own default.
    var lastSymbolChartRange: String = "" {
        didSet { scheduleSave() }
    }
    var lastPortfolioChartRange: String = "" {
        didSet { scheduleSave() }
    }

    static let supportedCurrencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD"]

    let fileURL: URL
    var isLoading = false
    var saveTask: Task<Void, Never>?

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            let fallback = FileManager.default.temporaryDirectory
            self.fileURL = fallback.appendingPathComponent("StockDock_data.json")
            return
        }
        let dirName = "StockDock"
        let dir = appSupport.appendingPathComponent(dirName, isDirectory: true)
        let oldDir = appSupport.appendingPathComponent("StockBar", isDirectory: true)
        if FileManager.default.fileExists(atPath: oldDir.path) && !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: dir)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")
        isLoading = true
        load()
        isLoading = false
    }

    func resetToDefaults() {
        preferredCurrency = "EUR"
        stockPriceCurrency = ""
        showExtendedHours = true
        showCompanyName = true
        showDayRange = true
        show52WeekBar = true
        showAbsoluteChange = true
        menuBarDisplay = "pnl"
        gainColorHex = ""
        lossColorHex = ""
        menuBarUseSystemColor = false
        percentDecimals = 1
        valueDecimals = -1
        menuBarHidePercent = false
        tickerShowName = false
        advancedPositions = false
        watchlistSort = "manual"
        appLanguage = "en"
        fontSizeLevel = 9
        fontFamily = "Inter Variable"
        appearanceRaw = AppearanceMode.default.rawValue
        showNewsTab = true
        lastSelectedTab = "Watchlist"
    }
}
