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

    /// Issue #7.4: show percentages with 2 decimals instead of 1 (off keeps the
    /// menu bar compact). Applies everywhere a % is shown.
    @Published var percentTwoDecimals: Bool = false {
        didSet { scheduleSave() }
    }

    /// Unlocks short positions (negative quantity) and per-holding leverage in
    /// the add/edit holding sheets. Off by default to keep the common long-only
    /// flow simple.
    @Published var advancedPositions: Bool = false {
        didSet { scheduleSave() }
    }

    /// Number of decimals used for percentage displays (1 or 2).
    var percentDecimals: Int { percentTwoDecimals ? 2 : 1 }

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

    var lastSelectedTab: String = "Watchlist"

    static let supportedCurrencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD"]

    /// Formats a plain number with a thousands grouping separator and locale-aware
    /// decimal separator, e.g. "1,234.56" (en) / "1.234,56" (it). Falls back to a
    /// non-grouped representation if the formatter ever fails.
    nonisolated static func formatNumber(_ value: Double, decimals: Int, locale: Locale = .autoupdatingCurrent) -> String {
        // Grouping is inserted manually (every 3 digits from the right) so every value
        // > 1,000 is separated regardless of the locale's CLDR rule (e.g. it/es only group
        // from 10,000 by default), and without needing macOS 15's `minimumGroupingDigits`.
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        let groupSep = formatter.groupingSeparator ?? ","
        let decSep = formatter.decimalSeparator ?? "."

        // %f always emits "." as the decimal separator, independent of locale.
        let rounded = String(format: "%.\(decimals)f", abs(value))
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
        if decimals > 0 { result += decSep + fracDigits }
        return (value < 0 ? "-" : "") + result
    }

    /// Formats an amount with the currency symbol *before* the figure, e.g.
    /// "€1,234.56", "+€820.00", "-€540.00". The sign (when shown) precedes the symbol.
    nonisolated static func formatAmount(_ value: Double, symbol: String, decimals: Int = 2, signed: Bool = false,
                             locale: Locale = .autoupdatingCurrent) -> String {
        let sign = signed ? (value >= 0 ? "+" : "-") : (value < 0 ? "-" : "")
        let magnitude = formatNumber(abs(value), decimals: decimals, locale: locale)
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

    func addPortfolio(name: String) {
        portfolios.append(Portfolio(name: name))
    }

    func renamePortfolio(id: UUID, name: String) {
        guard let index = portfolios.firstIndex(where: { $0.id == id }) else { return }
        portfolios[index].name = name
    }

    func deletePortfolio(at offsets: IndexSet) {
        let removedIds = offsets.map { portfolios[$0].id.uuidString }
        portfolios.remove(atOffsets: offsets)
        removedIds.forEach { portfolioNotifications[$0] = nil }
    }

    func deletePortfolio(id: UUID) {
        portfolios.removeAll { $0.id == id }
        portfolioNotifications[id.uuidString] = nil
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
        percentTwoDecimals = false
        tickerShowName = false
        advancedPositions = false
        watchlistSort = "manual"
        appLanguage = "en"
        fontSizeLevel = 9
        fontFamily = "Inter Variable"
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
        var discordWebhookURL: String?
        var discordEnabled: Bool?
        var gainColorHex: String?
        var lossColorHex: String?
        var menuBarUseSystemColor: Bool?
        var percentTwoDecimals: Bool?
        var tickerShowName: Bool?
        var watchlistSort: String?
        var symbolType: [String: String]?
        var appLanguage: String?
        var advancedPositions: Bool?
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
        let data = AppData(watchlist: watchlist, portfolios: portfolios, preferredCurrency: preferredCurrency, stockPriceCurrency: stockPriceCurrency, showExtendedHours: showExtendedHours, menuBarDisplay: menuBarDisplay, isinMap: isinMap, fontSizeLevel: fontSizeLevel, fontFamily: fontFamily, alerts: alerts, showCompanyName: showCompanyName, showDayRange: showDayRange, show52WeekBar: show52WeekBar, showAbsoluteChange: showAbsoluteChange, portfolioNotifications: portfolioNotifications, discordWebhookURL: discordWebhookURL, discordEnabled: discordEnabled, gainColorHex: gainColorHex, lossColorHex: lossColorHex, menuBarUseSystemColor: menuBarUseSystemColor, percentTwoDecimals: percentTwoDecimals, tickerShowName: tickerShowName, watchlistSort: watchlistSort, symbolType: symbolType, appLanguage: appLanguage, advancedPositions: advancedPositions)
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
            discordWebhookURL = decoded.discordWebhookURL ?? ""
            discordEnabled = decoded.discordEnabled ?? false
            gainColorHex = decoded.gainColorHex ?? ""
            lossColorHex = decoded.lossColorHex ?? ""
            menuBarUseSystemColor = decoded.menuBarUseSystemColor ?? false
            percentTwoDecimals = decoded.percentTwoDecimals ?? false
            tickerShowName = decoded.tickerShowName ?? false
            advancedPositions = decoded.advancedPositions ?? false
            watchlistSort = decoded.watchlistSort ?? "manual"
            symbolType = decoded.symbolType ?? [:]
            appLanguage = decoded.appLanguage ?? "en"
            showCompanyName = decoded.showCompanyName ?? true
            showDayRange = decoded.showDayRange ?? true
            show52WeekBar = decoded.show52WeekBar ?? true
            showAbsoluteChange = decoded.showAbsoluteChange ?? true
            fontSizeLevel = decoded.fontSizeLevel ?? 9
            fontFamily = decoded.fontFamily ?? "Inter Variable"
            FontRegistration.familyName = fontFamily
            FontRegistration.sizeOffset = CGFloat(fontSizeLevel - 9)
        } catch {
            // First launch or corrupted file — defaults are used
        }
    }
}
