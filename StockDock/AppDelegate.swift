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
    private var isRefreshing = false
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
            isRefreshing = true
            defer { isRefreshing = false }
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
                self.isRefreshing = true
                self.refreshTask = Task { @MainActor in
                    defer { self.isRefreshing = false }
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
                self.isRefreshing = true
                defer { self.isRefreshing = false }
                let symbols = Array(StockService.collectSymbols(storageService: self.storageService))
                await self.stockService.fetchQuotes(symbols: symbols)
                await self.stockService.refreshExchangeRates(storageService: self.storageService)
                self.updateMenuBarTitle()
                self.alertMonitor.check(quotes: self.stockService.quotes)
                self.portfolioMonitor.check()
                self.webSocketService.updateSymbols(Array(self.collectSymbols()))
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
        isRefreshing = false
        tickerTimer?.invalidate()
        tickerTimer = nil
        pendingTicks.removeAll()
        webSocketService.disconnect()
    }

    @objc private func handleWake() {
        refreshTask?.cancel()
        refreshTask = Task {
            isRefreshing = true
            defer { isRefreshing = false }
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

    private func updateMenuBarTitle() {
        let displayMode = storageService.menuBarDisplay

        if displayMode == "ticker" {
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

        switch displayMode {
        case "totalValue":
            title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol))"
            color = totalPnl >= 0 ? .systemGreen : .systemRed

        case "pnlPercent":
            let sign = totalPnlPct >= 0 ? "+" : ""
            title = " P&L \(sign)\(String(format: "%.1f", totalPnlPct))%"
            color = totalPnlPct >= 0 ? .systemGreen : .systemRed

        case "pnlFull":
            let pctSign = totalPnlPct >= 0 ? "+" : ""
            title = " \(StorageService.formatAmount(totalPnl, symbol: currSymbol, signed: true)) (\(pctSign)\(String(format: "%.1f", totalPnlPct))%)"
            color = totalPnl >= 0 ? .systemGreen : .systemRed

        case "bestStock":
            if let best = bestStock {
                let sign = best.changePercent >= 0 ? "+" : ""
                title = " \(best.symbol) \(sign)\(String(format: "%.1f", best.changePercent))%"
                color = best.changePercent >= 0 ? .systemGreen : .systemRed
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "worstStock":
            if let worst = worstStock {
                let sign = worst.changePercent >= 0 ? "+" : ""
                title = " \(worst.symbol) \(sign)\(String(format: "%.1f", worst.changePercent))%"
                color = worst.changePercent >= 0 ? .systemGreen : .systemRed
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "bestWorst":
            if let best = bestStock, let worst = worstStock, best.symbol != worst.symbol {
                let bSign = best.changePercent >= 0 ? "+" : ""
                let wSign = worst.changePercent >= 0 ? "+" : ""
                title = " ▲\(best.symbol) \(bSign)\(String(format: "%.1f", best.changePercent))%  ▼\(worst.symbol) \(wSign)\(String(format: "%.1f", worst.changePercent))%"
                color = .labelColor
            } else if let best = bestStock {
                let sign = best.changePercent >= 0 ? "+" : ""
                title = " \(best.symbol) \(sign)\(String(format: "%.1f", best.changePercent))%"
                color = best.changePercent >= 0 ? .systemGreen : .systemRed
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "portfolioRecap":
            let sign = totalPnlPct >= 0 ? "+" : ""
            title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol)) \(sign)\(String(format: "%.1f", totalPnlPct))%"
            color = totalPnl >= 0 ? .systemGreen : .systemRed

        case "ticker":
            let symbols = storageService.watchlist
            if symbols.isEmpty {
                title = " --"
                color = .secondaryLabelColor
            } else {
                let index = tickerIndex % symbols.count
                let symbol = symbols[index]
                if let quote = stockService.quotes[symbol] {
                    let pRate = stockService.priceRate(from: quote.currency)
                    let priceCurr = storageService.stockPriceCurrency
                    let sym = StorageService.currencySymbol(for: priceCurr.isEmpty ? quote.currency : priceCurr)
                    let sign = quote.changePercent >= 0 ? "+" : ""
                    title = " \(quote.symbol) \(sym)\(StorageService.formatNumber(quote.displayPrice(extendedHours: storageService.showExtendedHours) * pRate, decimals: 2)) \(sign)\(String(format: "%.1f", quote.changePercent))%"
                    color = quote.changePercent >= 0 ? .systemGreen : .systemRed
                } else {
                    title = " \(symbol)"
                    color = .secondaryLabelColor
                }
            }

        default: // "pnl"
            title = " P&L \(StorageService.formatAmount(totalPnl, symbol: currSymbol, signed: true))"
            color = totalPnl >= 0 ? .systemGreen : .systemRed
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
