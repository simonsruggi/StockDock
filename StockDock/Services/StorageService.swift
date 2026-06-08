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

    /// Maps symbol → ISIN for watchlist filtering
    @Published var isinMap: [String: String] = [:] {
        didSet { scheduleSave() }
    }

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
            portfolioNotifications[portfolioId.uuidString]?[i].lastStep = nil
            portfolioNotifications[portfolioId.uuidString]?[i].lastDay = nil
        }
    }

    /// Persists the anti-spam state after a notification fires (or primes silently).
    func updatePortfolioNotificationState(id: UUID, in portfolioId: UUID, lastStep: Double?, lastDay: String?) {
        guard let i = portfolioNotifications[portfolioId.uuidString]?.firstIndex(where: { $0.id == id }) else { return }
        portfolioNotifications[portfolioId.uuidString]?[i].lastStep = lastStep
        portfolioNotifications[portfolioId.uuidString]?[i].lastDay = lastDay
    }

    var lastSelectedTab: String = "Watchlist"

    static let supportedCurrencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD"]

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

    func addHolding(to portfolioId: UUID, symbol: String, quantity: Double, avgPrice: Double, purchaseDate: Date? = nil) {
        guard let index = portfolios.firstIndex(where: { $0.id == portfolioId }) else { return }
        let holding = Holding(symbol: symbol, quantity: quantity, avgPrice: avgPrice, purchaseDate: purchaseDate)
        portfolios[index].holdings.append(holding)
    }

    func removeHolding(from portfolioId: UUID, holdingId: UUID) {
        guard let pIndex = portfolios.firstIndex(where: { $0.id == portfolioId }) else { return }
        portfolios[pIndex].holdings.removeAll { $0.id == holdingId }
    }

    func updateHolding(in portfolioId: UUID, holdingId: UUID, quantity: Double, avgPrice: Double, purchaseDate: Date? = nil) {
        guard let pIndex = portfolios.firstIndex(where: { $0.id == portfolioId }),
              let hIndex = portfolios[pIndex].holdings.firstIndex(where: { $0.id == holdingId })
        else { return }
        portfolios[pIndex].holdings[hIndex].quantity = quantity
        portfolios[pIndex].holdings[hIndex].avgPrice = avgPrice
        portfolios[pIndex].holdings[hIndex].purchaseDate = purchaseDate
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
        let data = AppData(watchlist: watchlist, portfolios: portfolios, preferredCurrency: preferredCurrency, stockPriceCurrency: stockPriceCurrency, showExtendedHours: showExtendedHours, menuBarDisplay: menuBarDisplay, isinMap: isinMap, fontSizeLevel: fontSizeLevel, fontFamily: fontFamily, alerts: alerts, showCompanyName: showCompanyName, showDayRange: showDayRange, show52WeekBar: show52WeekBar, showAbsoluteChange: showAbsoluteChange, portfolioNotifications: portfolioNotifications, discordWebhookURL: discordWebhookURL, discordEnabled: discordEnabled)
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
