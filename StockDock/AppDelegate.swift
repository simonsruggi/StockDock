import AppKit
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private var popover: NSPopover?
    var portfolioWindow: NSWindow?
    var stockService = StockService.shared
    var storageService = StorageService.shared
    var webSocketService = WebSocketService.shared
    var timer: Timer?
    var tickerIndex = 0
    private var eventMonitor: Any?
    /// When the current refresh started. Nil = no refresh in flight. Used via
    /// `ConnectionSupervisor.refreshIsBlocking` instead of a bare Bool so a
    /// refresh Task cancelled by a sleep/wake race can't leave polling wedged.
    var refreshStartedAt: Date?
    var isRefreshing: Bool {
        ConnectionSupervisor.refreshIsBlocking(startedAt: refreshStartedAt, now: Date())
    }
    var refreshTask: Task<Void, Never>?
    var pendingTicks: [Yaticker] = []
    var tickBatchTimer: Timer?
    var tickerTimer: Timer?
    private var storageServiceObserver: AnyCancellable?
    private var symbolsObserver: AnyCancellable?
    lazy var alertMonitor = AlertMonitor(storage: storageService)
    lazy var portfolioMonitor = PortfolioMonitor(storage: storageService, stockService: stockService)
    let updaterViewModel = UpdaterViewModel()

    /// REST polling: quotes + exchange rates as WSS fallback
    static let restPollingInterval: TimeInterval = 60

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
    var tickFlushInterval: TimeInterval {
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

    func closePopover() {
        popover?.performClose(nil)
    }

    /// Keeps the popover on screen while one of our own panels (e.g. the import
    /// file picker) is in front, so the flow can continue inside the popover
    /// instead of it closing behind the panel.
    func holdPopoverOpen(_ hold: Bool) {
        popover?.behavior = hold ? .applicationDefined : .transient
    }

    /// Brings the popover back after a panel, so what follows (the import
    /// selection, an error) is visible.
    func showPopoverIfHidden() {
        if popover?.isShown != true { togglePopover() }
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
