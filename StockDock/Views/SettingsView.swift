import AppKit
import SwiftUI

/// Settings in the menu bar popover: collapsible categories, each a card of the
/// same rows and DS controls the desktop Settings uses. Sections live in the
/// `SettingsView+*.swift` extensions.
struct SettingsView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @State var showResetAlert = false
    @State var showClearAlerts = false
    @State var showClearPortfolioNotifs = false
    @FocusState var webhookFocused: Bool

    // Remembered across popover opens. General starts open, the rest collapsed.
    @AppStorage("settings.group.general") var groupGeneral = true
    @AppStorage("settings.group.currency") var groupCurrency = false
    @AppStorage("settings.group.positions") var groupPositions = false
    @AppStorage("settings.group.watchlist") var groupWatchlist = false
    @AppStorage("settings.group.menubar") var groupMenuBar = false
    @AppStorage("settings.group.notifications") var groupNotifications = false
    @AppStorage("settings.group.about") var groupAbout = false

    @ObservedObject var router = SearchRouter.shared

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                generalGroup
                currencyGroup
                positionsGroup
                watchlistGroup
                menuBarGroup
                notificationsGroup
                aboutGroup
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        // AppKit hands focus to the first text field (the tax rate) when the popover opens.
        .onAppear {
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            scrollToHighlight(proxy)
        }
        .onChange(of: router.highlightedSetting) { _, _ in scrollToHighlight(proxy) }
        }
        .dsAlert($showResetAlert, title: "Reset Settings",
                 message: "This will reset all settings to their defaults. Your portfolios and watchlist will not be affected.",
                 confirmTitle: "Reset", destructive: true) {
            storageService.resetToDefaults()
            Task { stockService.exchangeRates.removeAll(); await stockService.refreshAll(storageService: storageService) }
        }
        .dsAlert($showClearAlerts, title: "Clear all alerts",
                 message: "This will delete all your price alerts. This cannot be undone.",
                 confirmTitle: "Clear all", destructive: true) { storageService.removeAllAlerts() }
        .dsAlert($showClearPortfolioNotifs, title: "Clear all portfolio notifications",
                 message: "This will delete all portfolio notifications across every portfolio. This cannot be undone.",
                 confirmTitle: "Clear all", destructive: true) { storageService.removeAllPortfolioNotifications() }
    }

    /// Brings the row search landed on into view, once its category has opened.
    func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard let key = router.highlightedSetting else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(SearchAnchor.scrollID(key), anchor: .center) }
        }
    }

    /// Currency changes invalidate every converted figure: refetch the rates.
    func refreshRates() {
        stockService.exchangeRates.removeAll()
        Task { await stockService.refreshAll(storageService: storageService) }
    }

    static func currencyOptions(withOriginal: Bool) -> [(value: String, label: String)] {
        let codes = StorageService.supportedCurrencies.map { (value: $0, label: "\(StorageService.currencySymbol(for: $0)) \($0)") }
        return withOriginal ? [(value: "", label: "Original")] + codes : codes
    }
}
