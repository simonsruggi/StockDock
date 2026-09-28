import AppKit
import SwiftUI

extension AppDelegate {
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
