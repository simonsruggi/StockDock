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
    private var portfolioWindow: NSWindow?
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

    /// How often buffered ticks are published to the UI.
    ///
    /// Publishing a tick invalidates every view observing `StockService`, so each
    /// flush costs a full layout + rasterization pass over the open window —
    /// roughly 300ms of CPU with the Portfolio window up. At one flush a second
    /// that pinned the app around 60-70% CPU for the whole session.
    ///
    /// So: one second while the user is actually looking at StockDock, and a much
    /// lazier cadence when they're in another app. Ticks keep arriving and are
    /// still coalesced per symbol either way — only the *publish* rate changes, so
    /// nothing is lost, it just lands in bigger batches. Alerts and the menu-bar
    /// title update on flush too, which is why the background figure stays modest
    /// rather than being switched off entirely.
    private static let tickFlushActive: TimeInterval = 1.0
    private static let tickFlushBackground: TimeInterval = 5.0

    /// Live only while a window is on screen: with everything closed the app is a
    /// menu-bar title, and the ticker timer already drives that at its own pace.
    private var tickFlushInterval: TimeInterval {
        NSApp.isActive ? Self.tickFlushActive : Self.tickFlushBackground
    }

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
        // Appearance follows the user's preference (issue #11), applied reactively
        // via `.preferredColorScheme` on the SwiftUI root — not pinned here.
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
            recordSnapshots()
            startWebSocket()
        }

        // REST polling at low frequency for exchange rates and as WSS fallback
        scheduleRESTPolling()

        // Dev affordance: open the Portfolio window on launch for screenshots/testing.
        if ProcessInfo.processInfo.environment["SD_OPEN_WINDOW"] != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.showPortfolioWindow()
            }
        }

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

        // Coming back to the app publishes whatever arrived while it was in the
        // background right away, so the first glance is never up to
        // `tickFlushBackground` stale.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)

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
                    self.recordSnapshots()
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

    /// Flush buffered ticks at `tickFlushInterval` to avoid @Published spam
    private func scheduleTickFlush() {
        guard tickBatchTimer == nil else { return }
        tickBatchTimer = Timer.scheduledTimer(withTimeInterval: tickFlushInterval, repeats: false) { [weak self] _ in
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

    /// Captures a daily value/P&L snapshot per portfolio from the current quotes,
    /// for the Portfolio window's history chart. Skips a portfolio until every
    /// holding has a quote, so a partially-loaded feed can't record an understated
    /// value. `StorageService.recordSnapshot` keeps one entry per day.
    private func recordSnapshots() {
        for portfolio in storageService.portfolios {
            guard !portfolio.holdings.isEmpty else { continue }
            let inputs: [PortfolioValuation.Input] = portfolio.holdings.compactMap { holding in
                guard let quote = stockService.quotes[holding.symbol] else { return nil }
                return PortfolioValuation.Input(
                    holding: holding,
                    price: quote.displayPrice(extendedHours: storageService.showExtendedHours),
                    rate: stockService.rate(from: quote.currency),
                    costRate: stockService.rate(from: quote.currency, for: holding.purchaseDate)
                )
            }
            guard inputs.count == portfolio.holdings.count else { continue }
            let totals = PortfolioValuation.totals(inputs)
            storageService.recordSnapshot(for: portfolio.id, totalValue: totals.value, totalCost: totals.cost)
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
                self.recordSnapshots()
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
        let priceValue = quote.displayPrice(extendedHours: storageService.showExtendedHours) * pRate
        let price = StorageService.formatNumber(priceValue, decimals: storageService.resolvedPriceDecimals(symbol: quote.symbol, price: priceValue))
        // Issue #10: optionally drop the percentage from the menu-bar ticker.
        let pctPart = storageService.menuBarHidePercent
            ? ""
            : " \(sign)\(String(format: "%.\(storageService.percentDecimals)f", quote.changePercent))%"
        let title = " \(label) \(sym)\(price)\(pctPart)"
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
        var dailyPnl = 0.0
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                if let quote = stockService.quotes[holding.symbol] {
                    let rate = stockService.rate(from: quote.currency)
                    let displayPrice = quote.displayPrice(extendedHours: storageService.showExtendedHours)
                    totalValue += holding.marketValue(currentPrice: displayPrice) * rate
                    dailyPnl += holding.dailyPnl(priceChange: quote.effectiveChange(extendedHours: storageService.showExtendedHours)) * rate
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
        case "dailyPnl":
            title = " Daily P&L \(StorageService.formatAmount(dailyPnl, symbol: currSymbol, decimals: storageService.amountDecimals, signed: true))"
            color = dailyPnl >= 0 ? upColor : downColor

        case "totalValue":
            title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol, decimals: storageService.amountDecimals))"
            color = totalPnl >= 0 ? upColor : downColor

        case "pnlPercent":
            let sign = totalPnlPct >= 0 ? "+" : ""
            title = " P&L \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
            color = totalPnlPct >= 0 ? upColor : downColor

        case "pnlFull":
            let pctSign = totalPnlPct >= 0 ? "+" : ""
            let pctPart = storageService.menuBarHidePercent ? "" : " (\(pctSign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%)"
            title = " \(StorageService.formatAmount(totalPnl, symbol: currSymbol, decimals: storageService.amountDecimals, signed: true))\(pctPart)"
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
            let pctPart = storageService.menuBarHidePercent ? "" : " \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
            title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol, decimals: storageService.amountDecimals))\(pctPart)"
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
                    title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol, decimals: storageService.amountDecimals)) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
                    color = totalPnl >= 0 ? upColor : downColor
                }
            }

        default: // "pnl"
            title = " P&L \(StorageService.formatAmount(totalPnl, symbol: currSymbol, decimals: storageService.amountDecimals, signed: true))"
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

    /// Publish anything buffered under the background cadence immediately, and
    /// let the next batch be scheduled at the (now active) 1s interval.
    @objc private func handleDidBecomeActive() {
        tickBatchTimer?.invalidate()
        tickBatchTimer = nil
        flushTicks()
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
                    .environment(\.openWindowAction, { [weak self] in self?.showPortfolioWindow() })
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

    // MARK: - Portfolio Window

    /// Opens (or focuses) the full navigable Portfolio window. The menu-bar glance
    /// stays put; this is the "expanded" surface over the same shared state. While
    /// the window is up the app shows a Dock icon (regular policy) so it behaves
    /// like a normal app; closing it returns to accessory (menu-bar-only) mode.
    @objc func showPortfolioWindow() {
        let reusable = portfolioWindow?.isVisible ?? false
        NSLog("[StockDock] Open clicked — \(reusable ? "focusing existing window" : "creating new window")")
        closePopover()
        // Reuse the window only while it's actually on screen. Once closed with
        // the red button it's ordered out (and not reliably re-showable), so we
        // drop it and build a fresh one — otherwise "Open" would silently no-op.
        if let window = portfolioWindow, window.isVisible {
            bringWindowFront(window)
            return
        }
        portfolioWindow = nil

        let root = PortfolioWindowView()
            .environmentObject(stockService)
            .environmentObject(storageService)
            .environmentObject(updaterViewModel)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "StockDock"
        // One uninterrupted surface: transparent titlebar, no system title text
        // (the sidebar brand is the title), only floating traffic lights.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 1000, height: 680)
        // Appearance follows the user's preference (issue #11), applied reactively
        // via `.preferredColorScheme` on the SwiftUI root — not pinned here.
        window.contentViewController = NSHostingController(rootView: root)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("StockDockPortfolioWindow")
        window.center()
        portfolioWindow = window

        bringWindowFront(window)
    }

    /// Brings the desktop window reliably in front of every other app.
    ///
    /// StockDock is a menu-bar (accessory) app, and on macOS 14+ `activate` no
    /// longer lets a background app steal focus — so opening the window from the
    /// popover would leave it *behind* whatever app was active ("it doesn't
    /// open"). The fix: raise it at `.floating` level so it draws above other
    /// apps' windows, then drop back to `.normal` on the next runloop so it
    /// behaves like a normal window afterwards.
    private func bringWindowFront(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            window.level = .normal
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            NSLog("[StockDock] window shown — visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(NSStringFromRect(window.frame))")
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === portfolioWindow else { return }
        // Back to menu-bar-only mode once the window and popover are both gone.
        Task { @MainActor in
            let popoverShown = popover?.isShown ?? false
            if !popoverShown { NSApp.setActivationPolicy(.accessory) }
        }
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
