import AppKit
import Combine
import Sparkle
import SwiftUI

extension Notification.Name {
    static let popoverDidClose = Notification.Name("popoverDidClose")
}

final class SparkleDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        NSLog("[Sparkle] Appcast loaded OK, %d items", appcast.items.count)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("[Sparkle] Aborted: %@", error.localizedDescription)
    }
}

final class UpdaterViewModel: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    private let sparkleDelegate = SparkleDelegate()

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    var isAvailable: Bool {
        controller != nil
    }

    init() {
        if Bundle.main.infoDictionary?["SUFeedURL"] != nil {
            let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: sparkleDelegate, userDriverDelegate: nil)
            self.controller = c
        } else {
            self.controller = nil
        }
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var stockService = StockService.shared
    private var storageService = StorageService.shared
    private var webSocketService = WebSocketService.shared
    private var timer: Timer?
    private var tickerIndex = 0
    private var eventMonitor: Any?
    /// When the current refresh started. Nil = no refresh in flight. Used via
    /// `ConnectionSupervisor.refreshIsBlocking` instead of a bare Bool so a
    /// refresh Task cancelled by a sleep/wake race can't leave polling wedged.
    private var refreshStartedAt: Date?
    private var isRefreshing: Bool {
        ConnectionSupervisor.refreshIsBlocking(startedAt: refreshStartedAt, now: Date())
    }
    private var refreshTask: Task<Void, Never>?
    private var pendingTicks: [Yaticker] = []
    private var tickBatchTimer: Timer?
    private var tickerTimer: Timer?
    private var storageServiceObserver: AnyCancellable?
    private var symbolsObserver: AnyCancellable?
    private lazy var alertMonitor = AlertMonitor(storage: storageService)
    private lazy var portfolioMonitor = PortfolioMonitor(storage: storageService, stockService: stockService)
    let updaterViewModel = UpdaterViewModel()

    /// REST polling: quotes + exchange rates as WSS fallback
    private static let restPollingInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistration.registerFonts()

        // Ask for notification permission (no-op in dev without a bundle)
        NotificationManager.shared.requestAuthorization()

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "StockDock")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let p = NSPopover()
        p.contentSize = NSSize(width: 380, height: 520)
        p.behavior = .transient
        p.delegate = self
        popover = p

        refreshTask = Task {
            let start = Date()
            refreshStartedAt = start
            // Compare-and-clear: only clear if a newer refresh hasn't superseded
            // us, so a cancelled Task's defer can't unblock a live refresh.
            defer { if refreshStartedAt == start { refreshStartedAt = nil } }
            await stockService.refreshAll(storageService: storageService)
            guard !Task.isCancelled else { return }
            updateMenuBarTitle()
            alertMonitor.check(quotes: stockService.quotes)
            portfolioMonitor.check()
            startWebSocket()
        }

        // REST polling at low frequency for exchange rates and as WSS fallback
        scheduleRESTPolling()

        // Pause on system sleep, resume on wake
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        // Update menu bar when popover closes (user may have changed holdings/settings)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePopoverClosed),
            name: .popoverDidClose, object: nil)

        // Observe StorageService changes (portfolio edits, display mode, currency, etc.)
        storageServiceObserver = storageService.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarTitle()
            }
        }

        symbolsObserver = storageService.$portfolios
            .combineLatest(storageService.$watchlist)
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self, !self.isRefreshing else { return }
                let symbols = Array(self.collectSymbols())
                self.webSocketService.updateSymbols(symbols)
                self.refreshTask?.cancel()
                let start = Date()
                self.refreshStartedAt = start
                self.refreshTask = Task { @MainActor in
                    defer { if self.refreshStartedAt == start { self.refreshStartedAt = nil } }
                    await self.stockService.refreshAll(storageService: self.storageService)
                    self.updateMenuBarTitle()
                    self.alertMonitor.check(quotes: self.stockService.quotes)
                    self.portfolioMonitor.check()
                }
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        storageService.saveNow()
        timer?.invalidate()
        timer = nil
        tickBatchTimer?.invalidate()
        tickBatchTimer = nil
        tickerTimer?.invalidate()
        tickerTimer = nil
        webSocketService.disconnect()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - WebSocket

    private func startWebSocket() {
        let symbols = collectSymbols()
        guard !symbols.isEmpty else { return }

        webSocketService.onTick = { [weak self] ticker in
            guard let self else { return }
            self.pendingTicks.append(ticker)
            self.scheduleTickFlush()
        }

        webSocketService.connect(symbols: Array(symbols))
    }

    /// Flush buffered ticks max once per second to avoid @Published spam
    private func scheduleTickFlush() {
        guard tickBatchTimer == nil else { return }
        tickBatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickBatchTimer = nil
                self.flushTicks()
            }
        }
    }

    private func flushTicks() {
        guard !pendingTicks.isEmpty else { return }
        let ticks = pendingTicks
        pendingTicks.removeAll(keepingCapacity: false)

        // Keep only the latest tick per symbol
        var latest: [String: Yaticker] = [:]
        for tick in ticks {
            latest[tick.id] = tick
        }

        var changed = false
        for (_, tick) in latest {
            if stockService.applyTick(tick) {
                changed = true
            }
        }

        if changed {
            updateMenuBarTitle()
            alertMonitor.check(quotes: stockService.quotes)
            portfolioMonitor.check()
        }
    }

    private func collectSymbols() -> Set<String> {
        var symbols = Set(storageService.watchlist)
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                symbols.insert(holding.symbol)
            }
        }
        return symbols
    }


    // MARK: - Ticker Cycling

    private func startTickerTimer() {
        guard tickerTimer == nil else { return }
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickerIndex += 1
                self.updateMenuBarTitle()
            }
        }
    }

    private func stopTickerTimer() {
        tickerTimer?.invalidate()
        tickerTimer = nil
        tickerIndex = 0
    }

    // MARK: - REST Polling (exchange rates + fallback)

    private func scheduleRESTPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.restPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isRefreshing else { return }
                let start = Date()
                self.refreshStartedAt = start
                defer { if self.refreshStartedAt == start { self.refreshStartedAt = nil } }
                let symbols = Array(StockService.collectSymbols(storageService: self.storageService))
                await self.stockService.fetchQuotes(symbols: symbols)
                await self.stockService.refreshExchangeRates(storageService: self.storageService)
                self.updateMenuBarTitle()
                self.alertMonitor.check(quotes: self.stockService.quotes)
                self.portfolioMonitor.check()
                // Supervisor: revive the WebSocket if it silently died, otherwise
                // just keep its subscriptions current.
                self.webSocketService.ensureConnected(symbols: Array(self.collectSymbols()))
            }
        }
    }

    // MARK: - Sleep / Wake

    @objc private func handleSleep() {
        timer?.invalidate()
        timer = nil
        tickBatchTimer?.invalidate()
        tickBatchTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshStartedAt = nil
        tickerTimer?.invalidate()
        tickerTimer = nil
        pendingTicks.removeAll()
        webSocketService.disconnect()
    }

    @objc private func handleWake() {
        refreshTask?.cancel()
        refreshTask = Task {
            let start = Date()
            refreshStartedAt = start
            defer { if refreshStartedAt == start { refreshStartedAt = nil } }
            await stockService.refreshAll(storageService: storageService)
            guard !Task.isCancelled else { return }
            updateMenuBarTitle()
            startWebSocket()
        }
        scheduleRESTPolling()
    }

    private var menuBarFontSize: CGFloat {
        CGFloat(storageService.fontSizeLevel) + 5
    }

    /// Renders one watchlist slide for the menu bar ticker. Applies issue #8.2
    /// (show name vs symbol) and #8.3 (no currency symbol for indices).
    private func watchlistSlide(symbol: String, upColor: NSColor, downColor: NSColor) -> (title: String, color: NSColor) {
        guard let quote = stockService.quotes[symbol] else {
            return (" \(symbol)", .secondaryLabelColor)
        }
        let pRate = stockService.priceRate(from: quote.currency)
        let priceCurr = storageService.stockPriceCurrency
        // #8.3: indices have no currency, so don't prefix a currency symbol.
        let isIndex = StorageService.isIndex(symbol: quote.symbol, type: storageService.type(for: quote.symbol))
        let sym = isIndex ? "" : StorageService.currencySymbol(for: priceCurr.isEmpty ? quote.currency : priceCurr)
        // #8.2: prefer the readable name when the user opted in and it's available.
        let label = (storageService.tickerShowName && !quote.name.isEmpty) ? quote.name : quote.symbol
        let sign = quote.changePercent >= 0 ? "+" : ""
        let price = StorageService.formatNumber(quote.displayPrice(extendedHours: storageService.showExtendedHours) * pRate, decimals: 2)
        let pct = String(format: "%.\(storageService.percentDecimals)f", quote.changePercent)
        let title = " \(label) \(sym)\(price) \(sign)\(pct)%"
        return (title, quote.changePercent >= 0 ? upColor : downColor)
    }

    private func updateMenuBarTitle() {
        let displayMode = storageService.menuBarDisplay

        if displayMode == "ticker" || displayMode == "tickerPortfolio" {
            if tickerTimer == nil { startTickerTimer() }
        } else {
            stopTickerTimer()
        }

        // Icon only
        if displayMode == "icon" {
            statusItem?.button?.attributedTitle = NSAttributedString(string: "")
            statusItem?.button?.title = ""
            statusItem?.button?.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "StockDock")
            return
        }

        // Compute portfolio stats
        var totalValue = 0.0
        var totalCost = 0.0
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                if let quote = stockService.quotes[holding.symbol] {
                    let rate = stockService.rate(from: quote.currency)
                    let displayPrice = quote.displayPrice(extendedHours: storageService.showExtendedHours)
                    totalValue += holding.marketValue(currentPrice: displayPrice) * rate
                    let costRate = stockService.rate(from: quote.currency, for: holding.purchaseDate)
                    totalCost += (holding.avgPrice * holding.quantity) * costRate
                }
            }
        }
        let totalPnl = totalValue - totalCost
        let totalPnlPct = totalCost > 0 ? (totalPnl / totalCost) * 100 : 0

        // Find best/worst watchlist stock by daily change %
        let bestStock = storageService.watchlist.compactMap { stockService.quotes[$0] }
            .max(by: { $0.changePercent < $1.changePercent })
        let worstStock = storageService.watchlist.compactMap { stockService.quotes[$0] }
            .min(by: { $0.changePercent < $1.changePercent })

        let currSymbol = StorageService.currencySymbol(for: storageService.preferredCurrency)
        let title: String
        let color: NSColor

        // Issue #7.1: customizable gain/loss colors. "Use system color" overrides both
        // with the always-readable label color (direction stays in the +/- and ▲▼).
        let upColor: NSColor = storageService.menuBarUseSystemColor ? .labelColor : storageService.gainColor
        let downColor: NSColor = storageService.menuBarUseSystemColor ? .labelColor : storageService.lossColor

        switch displayMode {
        case "totalValue":
            title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol))"
            color = totalPnl >= 0 ? upColor : downColor

        case "pnlPercent":
            let sign = totalPnlPct >= 0 ? "+" : ""
            title = " P&L \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
            color = totalPnlPct >= 0 ? upColor : downColor

        case "pnlFull":
            let pctSign = totalPnlPct >= 0 ? "+" : ""
            title = " \(StorageService.formatAmount(totalPnl, symbol: currSymbol, signed: true)) (\(pctSign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%)"
            color = totalPnl >= 0 ? upColor : downColor

        case "bestStock":
            if let best = bestStock {
                let sign = best.changePercent >= 0 ? "+" : ""
                title = " \(best.symbol) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", best.changePercent))%"
                color = best.changePercent >= 0 ? upColor : downColor
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "worstStock":
            if let worst = worstStock {
                let sign = worst.changePercent >= 0 ? "+" : ""
                title = " \(worst.symbol) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", worst.changePercent))%"
                color = worst.changePercent >= 0 ? upColor : downColor
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "bestWorst":
            if let best = bestStock, let worst = worstStock, best.symbol != worst.symbol {
                let bSign = best.changePercent >= 0 ? "+" : ""
                let wSign = worst.changePercent >= 0 ? "+" : ""
                title = " ▲\(best.symbol) \(bSign)\(String(format: "%.\(storageService.percentDecimals)f", best.changePercent))%  ▼\(worst.symbol) \(wSign)\(String(format: "%.\(storageService.percentDecimals)f", worst.changePercent))%"
                color = .labelColor
            } else if let best = bestStock {
                let sign = best.changePercent >= 0 ? "+" : ""
                title = " \(best.symbol) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", best.changePercent))%"
                color = best.changePercent >= 0 ? upColor : downColor
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "portfolioRecap":
            let sign = totalPnlPct >= 0 ? "+" : ""
            title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol)) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
            color = totalPnl >= 0 ? upColor : downColor

        case "ticker":
            // #8.1: cycle in the user-selected order (as added / by type / alphabetical).
            let symbols = StorageService.tickerOrder(storageService.watchlist, mode: storageService.watchlistSort, types: storageService.symbolType)
            if symbols.isEmpty {
                title = " --"
                color = .secondaryLabelColor
            } else {
                let symbol = symbols[tickerIndex % symbols.count]
                (title, color) = watchlistSlide(symbol: symbol, upColor: upColor, downColor: downColor)
            }

        case "tickerPortfolio":
            // Issue #7.3: cycle through the watchlist AND a portfolio recap slide.
            let symbols = StorageService.tickerOrder(storageService.watchlist, mode: storageService.watchlistSort, types: storageService.symbolType)
            let hasPortfolio = storageService.portfolios.contains { !$0.holdings.isEmpty }
            let slideCount = symbols.count + (hasPortfolio ? 1 : 0)
            if slideCount == 0 {
                title = " --"
                color = .secondaryLabelColor
            } else {
                let index = tickerIndex % slideCount
                if index < symbols.count {
                    // Watchlist slide (same rendering as the "ticker" mode)
                    (title, color) = watchlistSlide(symbol: symbols[index], upColor: upColor, downColor: downColor)
                } else {
                    // Portfolio recap slide
                    let sign = totalPnlPct >= 0 ? "+" : ""
                    title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol)) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
                    color = totalPnl >= 0 ? upColor : downColor
                }
            }

        default: // "pnl"
            title = " P&L \(StorageService.formatAmount(totalPnl, symbol: currSymbol, signed: true))"
            color = totalPnl >= 0 ? upColor : downColor
        }

        statusItem?.button?.image = nil
        statusItem?.button?.title = title

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: FontRegistration.monospacedDigitsFont(size: menuBarFontSize, weight: .medium)
        ]
        statusItem?.button?.attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }

    @objc private func handlePopoverClosed() {
        updateMenuBarTitle()
        // Update WSS subscriptions in case symbols changed
        webSocketService.updateSymbols(Array(collectSymbols()))
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            if popover.contentViewController == nil {
                let contentView = ContentView()
                    .environmentObject(stockService)
                    .environmentObject(storageService)
                    .environmentObject(updaterViewModel)
                popover.contentViewController = NSHostingController(rootView: contentView)
            }
            let rect = NSRect(x: 0, y: 0, width: button.bounds.width, height: 0)
            popover.show(relativeTo: rect, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        let hasOtherWindows = NSApp.windows.contains { $0.isVisible && $0.className != "_NSPopoverWindow" }
        if !hasOtherWindows {
            NSApp.setActivationPolicy(.accessory)
        }
        NotificationCenter.default.post(name: .popoverDidClose, object: nil)
    }
}
