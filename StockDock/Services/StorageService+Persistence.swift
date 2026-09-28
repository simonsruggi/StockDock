import Foundation

extension StorageService {
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

    func scheduleSave() {
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

    func load() {
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
