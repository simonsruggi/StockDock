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

    // MARK: - Alerts

    func addAlert(_ alert: PriceAlert) {
        alerts.append(alert)
    }

    func removeAlert(id: UUID) {
        alerts.removeAll { $0.id == id }
    }

    func removeAllAlerts() {
        alerts.removeAll()
    }

    func setAlertEnabled(id: UUID, enabled: Bool) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].isEnabled = enabled
        if enabled { alerts[i].lastTriggeredAt = nil }
    }

    /// Marks an alert as fired: records the time and disables it (one-shot).
    func markAlertTriggered(id: UUID, at date: Date = Date()) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].isEnabled = false
        alerts[i].lastTriggeredAt = date
    }

    func alerts(for symbol: String) -> [PriceAlert] {
        alerts.filter { $0.symbol == symbol }
    }

    // MARK: - Portfolio notifications

    func notifications(for portfolioId: UUID) -> [PortfolioNotification] {
        portfolioNotifications[portfolioId.uuidString] ?? []
    }

    func addPortfolioNotification(_ notification: PortfolioNotification, to portfolioId: UUID) {
        portfolioNotifications[portfolioId.uuidString, default: []].append(notification)
    }

    func removeAllPortfolioNotifications() {
        portfolioNotifications = [:]
    }

    func removePortfolioNotification(id: UUID, from portfolioId: UUID) {
        portfolioNotifications[portfolioId.uuidString]?.removeAll { $0.id == id }
        if portfolioNotifications[portfolioId.uuidString]?.isEmpty == true {
            portfolioNotifications[portfolioId.uuidString] = nil
        }
    }

    func setPortfolioNotificationEnabled(id: UUID, in portfolioId: UUID, enabled: Bool) {
        guard let i = portfolioNotifications[portfolioId.uuidString]?.firstIndex(where: { $0.id == id }) else { return }
        portfolioNotifications[portfolioId.uuidString]?[i].isEnabled = enabled
        if enabled {
            portfolioNotifications[portfolioId.uuidString]?[i].lastStepUp = nil
            portfolioNotifications[portfolioId.uuidString]?[i].lastStepDown = nil
            portfolioNotifications[portfolioId.uuidString]?[i].lastDay = nil
        }
    }

    /// Persists the anti-spam high-water state after a notification fires (or primes silently).
    func updatePortfolioNotificationState(id: UUID, in portfolioId: UUID,
                                          lastStepUp: Double?, lastStepDown: Double?, lastDay: String?) {
        guard let i = portfolioNotifications[portfolioId.uuidString]?.firstIndex(where: { $0.id == id }) else { return }
        portfolioNotifications[portfolioId.uuidString]?[i].lastStepUp = lastStepUp
        portfolioNotifications[portfolioId.uuidString]?[i].lastStepDown = lastStepDown
        portfolioNotifications[portfolioId.uuidString]?[i].lastDay = lastDay
    }

    // MARK: - Portfolio snapshots

    func snapshots(for portfolioId: UUID) -> [PortfolioSnapshot] {
        portfolioSnapshots[portfolioId.uuidString] ?? []
    }

    /// Records a portfolio's value/cost for today, keeping one snapshot per day
    /// (today's is replaced so the latest intraday value wins). The date is
    /// normalized to the start of the local day. No-ops for an empty portfolio so
    /// the history doesn't fill with zeros before any holdings exist.
    func recordSnapshot(for portfolioId: UUID, totalValue: Double, totalCost: Double,
                        now: Date = Date(), calendar: Calendar = .current) {
        guard totalValue != 0 || totalCost != 0 else { return }
        let snapshot = PortfolioSnapshot(date: calendar.startOfDay(for: now),
                                         totalValue: totalValue, totalCost: totalCost)
        let key = portfolioId.uuidString
        portfolioSnapshots[key] = SnapshotLog.upsert(snapshot, into: portfolioSnapshots[key] ?? [], calendar: calendar)
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

    /// Issue #10: how many decimals to show for a *market price*. Two decimals is
    /// right for normal stocks, but forex pairs (e.g. CADUSD=X = 0.7119) and any
    /// sub-dollar instrument (penny stocks, low-priced crypto) lose meaningful
    /// precision at 2 decimals, so they get 4. Big forex crosses (e.g. USDJPY ≈ 149)
    /// stay at 2 to avoid pointless trailing zeros.
    nonisolated static func priceDecimals(symbol: String, price: Double) -> Int {
        let isForex = symbol.uppercased().hasSuffix("=X")
        let magnitude = abs(price)
        if isForex { return magnitude >= 50 ? 2 : 4 }
        if magnitude > 0 && magnitude < 1 { return 4 }
        return 2
    }

    /// Formats a share count: whole numbers stay whole ("12"), fractional shares
    /// keep two decimals ("12.50"). Negative = a short position, kept signed.
    nonisolated static func formatQuantity(_ qty: Double) -> String {
        qty == qty.rounded(.down) ? String(format: "%.0f", qty) : String(format: "%.2f", qty)
    }

    /// Formats a plain number with a thousands grouping separator and locale-aware
    /// decimal separator, e.g. "1,234.56" (en) / "1.234,56" (it). Falls back to a
    /// non-grouped representation if the formatter ever fails.
    nonisolated static func formatNumber(_ value: Double, decimals: Int, truncateZeros: Bool = false, locale: Locale = .autoupdatingCurrent) -> String {
        // Grouping is inserted manually (every 3 digits from the right) so every value
        // > 1,000 is separated regardless of the locale's CLDR rule (e.g. it/es only group
        // from 10,000 by default), and without needing macOS 15's `minimumGroupingDigits`.
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal

        let groupSep = formatter.groupingSeparator ?? ","
        let decSep = formatter.decimalSeparator ?? "."

        // Reuse the formatter to produce the raw digits: en_US + no grouping yields a
        // plain "1234.56" we regroup below, and minimumFractionDigits = 0 lets us drop
        // trailing zeros when `truncateZeros` is set — something `%f` can't do.
        formatter.locale = Locale(identifier: "en_US")
        formatter.groupingSeparator = ""
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = truncateZeros ? 0 : decimals

        // Falls back to a non-grouped %f representation if the formatter ever fails.
        let rounded = formatter.string(from: NSNumber(value: abs(value)))
            ?? String(format: "%.\(decimals)f", abs(value))
        let parts = rounded.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intDigits = String(parts[0])
        let fracDigits = parts.count > 1 ? String(parts[1]) : ""

        var grouped = ""
        var count = 0
        for ch in intDigits.reversed() {
            if count > 0 && count % 3 == 0 { grouped.append(contentsOf: groupSep.reversed()) }
            grouped.append(ch)
            count += 1
        }
        var result = String(grouped.reversed())
        if !fracDigits.isEmpty { result += decSep + fracDigits }
        return (value < 0 ? "-" : "") + result
    }

    /// Formats an amount with the currency symbol *before* the figure, e.g.
    /// "€1,234.56", "+€820.00", "-€540.00". The sign (when shown) precedes the symbol.
    nonisolated static func formatAmount(_ value: Double, symbol: String, decimals: Int = 2, signed: Bool = false, truncateZeros: Bool = false,
                             locale: Locale = .autoupdatingCurrent) -> String {
        let sign = signed ? (value >= 0 ? "+" : "-") : (value < 0 ? "-" : "")
        let magnitude = formatNumber(abs(value), decimals: decimals, truncateZeros: truncateZeros, locale: locale)
        return "\(sign)\(symbol)\(magnitude)"
    }

    /// Issue #8.3: true when a symbol is a market index, which has no associated
    /// currency (so no currency symbol should prefix its value). Uses the resolved
    /// Yahoo type when known, falling back to the "^" convention (e.g. ^GSPC).
    nonisolated static func isIndex(symbol: String, type: String?) -> Bool {
        if let t = type, !t.isEmpty { return t.uppercased() == "INDEX" }
        return symbol.hasPrefix("^")
    }

    /// Issue #8.1: orders watchlist symbols for the menu bar ticker cycle.
    /// "type" groups by asset class (stocks → ETFs → indices → futures → …),
    /// keeping the original relative order within each group (stable). Symbols with
    /// an unknown type sort last. "alpha" sorts alphabetically. "manual" (default)
    /// preserves the as-added order.
    nonisolated static func tickerOrder(_ symbols: [String], mode: String, types: [String: String]) -> [String] {
        switch mode {
        case "alpha":
            return symbols.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case "type":
            func rank(_ symbol: String) -> Int {
                switch (types[symbol] ?? "").uppercased() {
                case "EQUITY": return 0
                case "ETF": return 1
                case "INDEX": return 2
                case "FUTURE": return 3
                case "MUTUALFUND": return 4
                case "CURRENCY": return 5
                case "CRYPTOCURRENCY": return 6
                case "": return 100 // unknown type → end
                default: return 50
                }
            }
            return symbols.enumerated()
                .sorted { a, b in
                    let ra = rank(a.element), rb = rank(b.element)
                    return ra != rb ? ra < rb : a.offset < b.offset // stable within a group
                }
                .map { $0.element }
        default:
            return symbols
        }
    }

    /// Orders rows by their pre/post-market % move (the meaningful figure during
    /// extended hours), NOT by the raw extended-hours price. Rows without an
    /// extended-hours quote (`nil` percent) always sink to the bottom, regardless
    /// of sort direction. Descending puts the biggest movers first.
    nonisolated static func sortedByExtendedPercent<Row>(
        _ rows: [Row], ascending: Bool, percent: (Row) -> Double?
    ) -> [Row] {
        rows.sorted { a, b in
            switch (percent(a), percent(b)) {
            case let (x?, y?): return ascending ? x < y : x > y
            case (_?, nil):    return true   // a has ext data, b doesn't → a first
            case (nil, _?):    return false  // b has ext data → b first
            case (nil, nil):   return false
            }
        }
    }

    static func currencySymbol(for code: String) -> String {
        switch code {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        case "CHF": return "CHF"
        case "JPY": return "¥"
        case "CAD": return "C$"
        case "AUD": return "A$"
        default: return code
        }
    }

    private let fileURL: URL
    private var isLoading = false
    private var saveTask: Task<Void, Never>?

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

    func addToWatchlist(_ symbol: String) {
        guard !watchlist.contains(symbol) else { return }
        watchlist.append(symbol)
    }

    func removeFromWatchlist(_ symbol: String) {
        watchlist.removeAll { $0 == symbol }
    }

    func moveWatchlistItem(from source: IndexSet, to destination: Int) {
        watchlist.move(fromOffsets: source, toOffset: destination)
    }

    /// Nudges a symbol one place up (`-1`) or down (`+1`) in the manual order.
    /// Returns false at the ends of the list, so callers can leave the UI alone.
    @discardableResult
    func moveWatchlistItem(_ symbol: String, by delta: Int) -> Bool {
        guard let i = watchlist.firstIndex(of: symbol) else { return false }
        let j = i + delta
        guard j >= 0, j < watchlist.count else { return false }
        watchlist.swapAt(i, j)
        return true
    }

    func addPortfolio(name: String) {
        portfolios.append(Portfolio(name: name))
    }

    func renamePortfolio(id: UUID, name: String) {
        guard let index = portfolios.firstIndex(where: { $0.id == id }) else { return }
        portfolios[index].name = name
    }

    /// Issue #14: the portfolios that make up every *combined* figure — the menu
    /// bar, "All Portfolios", the window's footer total.
    ///
    /// This is deliberately the single place the filter lives. The aggregation
    /// used to be open-coded in five files, and the menu bar disagreeing with the
    /// window about the total is exactly the bug that split would produce.
    var countedPortfolios: [Portfolio] {
        portfolios.filter { !$0.isExcludedFromTotal }
    }

    /// Includes/excludes a portfolio from the combined total.
    func setExcludedFromTotal(_ excluded: Bool, id: UUID) {
        guard let index = portfolios.firstIndex(where: { $0.id == id }) else { return }
        portfolios[index].excludedFromTotal = excluded ? true : nil
    }

    func deletePortfolio(at offsets: IndexSet) {
        let removedIds = offsets.map { portfolios[$0].id.uuidString }
        portfolios.remove(atOffsets: offsets)
        removedIds.forEach {
            portfolioNotifications[$0] = nil
            portfolioSnapshots[$0] = nil
        }
    }

    func deletePortfolio(id: UUID) {
        portfolios.removeAll { $0.id == id }
        portfolioNotifications[id.uuidString] = nil
        portfolioSnapshots[id.uuidString] = nil
    }

    func addHolding(to portfolioId: UUID, symbol: String, quantity: Double, avgPrice: Double, purchaseDate: Date? = nil, leverage: Double? = nil) {
        guard let index = portfolios.firstIndex(where: { $0.id == portfolioId }) else { return }
        let holding = Holding(symbol: symbol, quantity: quantity, avgPrice: avgPrice, purchaseDate: purchaseDate, leverage: leverage)
        portfolios[index].holdings.append(holding)
    }

    func removeHolding(from portfolioId: UUID, holdingId: UUID) {
        guard let pIndex = portfolios.firstIndex(where: { $0.id == portfolioId }) else { return }
        portfolios[pIndex].holdings.removeAll { $0.id == holdingId }
    }

    func updateHolding(in portfolioId: UUID, holdingId: UUID, quantity: Double, avgPrice: Double, purchaseDate: Date? = nil, leverage: Double? = nil) {
        guard let pIndex = portfolios.firstIndex(where: { $0.id == portfolioId }),
              let hIndex = portfolios[pIndex].holdings.firstIndex(where: { $0.id == holdingId })
        else { return }
        portfolios[pIndex].holdings[hIndex].quantity = quantity
        portfolios[pIndex].holdings[hIndex].avgPrice = avgPrice
        portfolios[pIndex].holdings[hIndex].purchaseDate = purchaseDate
        portfolios[pIndex].holdings[hIndex].leverage = leverage
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

    // MARK: - Export / Import

    struct PortfolioExport: Codable {
        var version: Int = 1
        var exportDate: Date
        var portfolios: [Portfolio]
    }

    func exportPortfolios(_ portfoliosToExport: [Portfolio]) -> Data? {
        let export = PortfolioExport(exportDate: Date(), portfolios: portfoliosToExport)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(export)
    }

    func importPortfolios(from data: Data) -> [Portfolio]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let export = try? decoder.decode(PortfolioExport.self, from: data) else { return nil }
        return export.portfolios
    }

    func mergeImportedPortfolios(_ imported: [Portfolio]) {
        for var portfolio in imported {
            portfolio.id = UUID()
            for i in portfolio.holdings.indices {
                portfolio.holdings[i].id = UUID()
            }
            let baseName = portfolio.name
            var name = baseName
            var counter = 2
            while portfolios.contains(where: { $0.name == name }) {
                name = "\(baseName) (\(counter))"
                counter += 1
            }
            portfolio.name = name
            portfolios.append(portfolio)
        }
    }

    // MARK: - Persistence

    private struct AppData: Codable {
        var watchlist: [String]
        var portfolios: [Portfolio]
        var preferredCurrency: String?
        var stockPriceCurrency: String?
        var showExtendedHours: Bool?
        var menuBarDisplay: String?
        var isinMap: [String: String]?
        var fontSizeLevel: Int?
        var fontFamily: String?
        var alerts: [PriceAlert]?
        var showCompanyName: Bool?
        var showDayRange: Bool?
        var show52WeekBar: Bool?
        var showAbsoluteChange: Bool?
        var portfolioNotifications: [String: [PortfolioNotification]]?
        var portfolioSnapshots: [String: [PortfolioSnapshot]]?
        var discordWebhookURL: String?
        var discordEnabled: Bool?
        var gainColorHex: String?
        var lossColorHex: String?
        var menuBarUseSystemColor: Bool?
        var percentTwoDecimals: Bool?   // legacy (pre-#10) — migrated on decode
        var percentDecimals: Int?
        var valueDecimals: Int?
        var menuBarHidePercent: Bool?
        var tickerShowName: Bool?
        var watchlistSort: String?
        var symbolType: [String: String]?
        var symbolAlias: [String: String]?
        var appLanguage: String?
        var advancedPositions: Bool?
        var appearanceRaw: String?
        var showNewsTab: Bool?
        var lastSymbolChartRange: String?
        var lastPortfolioChartRange: String?
    }

    private func scheduleSave() {
        guard !isLoading else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            self.performSave()
        }
    }

    private func performSave() {
        let data = AppData(watchlist: watchlist, portfolios: portfolios, preferredCurrency: preferredCurrency, stockPriceCurrency: stockPriceCurrency, showExtendedHours: showExtendedHours, menuBarDisplay: menuBarDisplay, isinMap: isinMap, fontSizeLevel: fontSizeLevel, fontFamily: fontFamily, alerts: alerts, showCompanyName: showCompanyName, showDayRange: showDayRange, show52WeekBar: show52WeekBar, showAbsoluteChange: showAbsoluteChange, portfolioNotifications: portfolioNotifications, portfolioSnapshots: portfolioSnapshots, discordWebhookURL: discordWebhookURL, discordEnabled: discordEnabled, gainColorHex: gainColorHex, lossColorHex: lossColorHex, menuBarUseSystemColor: menuBarUseSystemColor, percentTwoDecimals: nil, percentDecimals: percentDecimals, valueDecimals: valueDecimals, menuBarHidePercent: menuBarHidePercent, tickerShowName: tickerShowName, watchlistSort: watchlistSort, symbolType: symbolType, symbolAlias: symbolAlias, appLanguage: appLanguage, advancedPositions: advancedPositions, appearanceRaw: appearanceRaw, showNewsTab: showNewsTab, lastSymbolChartRange: lastSymbolChartRange, lastPortfolioChartRange: lastPortfolioChartRange)
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            // Error saving is non-fatal; data will be retried on next change
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        performSave()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(AppData.self, from: data)
            watchlist = decoded.watchlist
            portfolios = decoded.portfolios
            preferredCurrency = decoded.preferredCurrency ?? "EUR"
            stockPriceCurrency = decoded.stockPriceCurrency ?? ""
            showExtendedHours = decoded.showExtendedHours ?? true
            menuBarDisplay = decoded.menuBarDisplay ?? "pnl"
            isinMap = decoded.isinMap ?? [:]
            alerts = decoded.alerts ?? []
            portfolioNotifications = decoded.portfolioNotifications ?? [:]
            portfolioSnapshots = decoded.portfolioSnapshots ?? [:]
            discordWebhookURL = decoded.discordWebhookURL ?? ""
            discordEnabled = decoded.discordEnabled ?? false
            gainColorHex = decoded.gainColorHex ?? ""
            lossColorHex = decoded.lossColorHex ?? ""
            menuBarUseSystemColor = decoded.menuBarUseSystemColor ?? false
            // #10: migrate the old on/off toggle (2 vs 1) to the free decimal count.
            percentDecimals = decoded.percentDecimals ?? (decoded.percentTwoDecimals == true ? 2 : 1)
            valueDecimals = decoded.valueDecimals ?? -1
            menuBarHidePercent = decoded.menuBarHidePercent ?? false
            tickerShowName = decoded.tickerShowName ?? false
            advancedPositions = decoded.advancedPositions ?? false
            watchlistSort = decoded.watchlistSort ?? "manual"
            symbolType = decoded.symbolType ?? [:]
            symbolAlias = decoded.symbolAlias ?? [:]
            appLanguage = decoded.appLanguage ?? "en"
            showCompanyName = decoded.showCompanyName ?? true
            showDayRange = decoded.showDayRange ?? true
            show52WeekBar = decoded.show52WeekBar ?? true
            showAbsoluteChange = decoded.showAbsoluteChange ?? true
            fontSizeLevel = decoded.fontSizeLevel ?? 9
            fontFamily = decoded.fontFamily ?? "Inter Variable"
            appearanceRaw = decoded.appearanceRaw ?? AppearanceMode.default.rawValue
            showNewsTab = decoded.showNewsTab ?? true
            lastSymbolChartRange = decoded.lastSymbolChartRange ?? ""
            lastPortfolioChartRange = decoded.lastPortfolioChartRange ?? ""
            FontRegistration.familyName = fontFamily
            FontRegistration.sizeOffset = CGFloat(fontSizeLevel - 9)
        } catch {
            // First launch or corrupted file — defaults are used
        }
    }
}
