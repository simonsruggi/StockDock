import SwiftUI
import AppKit

/// Desktop settings, dressed in the app's own card system (white premium cards,
/// hairline dividers, emerald controls) so the tab matches Overview/Watchlist
/// instead of the system-gray grouped form. Same bindings as the popover —
/// changes apply everywhere at once.
struct SettingsWideView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @State private var showResetAlert = false
    @State private var showClearAlerts = false
    @State private var showClearPortfolioNotifs = false
    @FocusState private var webhookFocused: Bool

    var body: some View {
        PageScaffold("Settings", caption: "Preferences are shared with the menu bar.") {
            EmptyView()
        } content: {
            ScrollView {
                // Two balanced columns so Settings occupies the same content
                // width as every other tab.
                HStack(alignment: .top, spacing: DS.gap) {
                    VStack(alignment: .leading, spacing: DS.gap) {
                        generalCard
                        menuBarCard
                        if !storageService.alerts.isEmpty { alertsCard }
                        let withNotifs = storageService.portfolios.filter { !storageService.notifications(for: $0.id).isEmpty }
                        if !withNotifs.isEmpty { portfolioNotifsCard(withNotifs) }
                    }
                    VStack(alignment: .leading, spacing: DS.gap) {
                        tradingCard
                        watchlistCard
                        notificationsCard
                        appearanceCard
                        aboutCard
                    }
                }
                .pageColumn()
                .padding(.top, 4)
            }
        }
        .navigationTitle("Settings")
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

    // MARK: - Cards

    private var generalCard: some View {
        SettingsCard(title: "General") {
            SettingRow("Language") {
                DSPicker(options: StorageService.supportedLanguages.map { ($0.code, $0.name) },
                         selection: $storageService.appLanguage, width: 200)
            }
            SettingDivider()
            SettingRow("Stock price currency", caption: "How individual quotes are shown") {
                DSPicker(options: [("", "Original")] + StorageService.supportedCurrencies.map { ($0, "\(StorageService.currencySymbol(for: $0)) \($0)") },
                         selection: $storageService.stockPriceCurrency, width: 200)
                    .onChange(of: storageService.stockPriceCurrency) {
                        stockService.exchangeRates.removeAll()
                        Task { await stockService.refreshAll(storageService: storageService) }
                    }
            }
            SettingDivider()
            SettingRow("Portfolio currency", caption: "Totals and P&L are converted here") {
                DSPicker(options: StorageService.supportedCurrencies.map { ($0, "\(StorageService.currencySymbol(for: $0)) \($0)") },
                         selection: $storageService.preferredCurrency, width: 200)
                    .onChange(of: storageService.preferredCurrency) {
                        stockService.exchangeRates.removeAll()
                        Task { await stockService.refreshAll(storageService: storageService) }
                    }
            }
        }
    }

    private var tradingCard: some View {
        SettingsCard(title: "Trading") {
            SettingToggle("Short positions & leverage",
                          caption: "Unlocks negative quantity and a leverage field",
                          isOn: $storageService.advancedPositions)
            SettingDivider()
            SettingToggle("Extended hours (Pre/Post)",
                          caption: "Show pre-market and after-hours prices",
                          isOn: $storageService.showExtendedHours)
        }
    }

    private var watchlistCard: some View {
        SettingsCard(title: "Watchlist row details") {
            SettingToggle("Company name", isOn: $storageService.showCompanyName)
            SettingDivider()
            SettingToggle("Day range (low – high)", isOn: $storageService.showDayRange)
            SettingDivider()
            SettingToggle("52-week range bar", isOn: $storageService.show52WeekBar)
            SettingDivider()
            SettingToggle("Absolute change value", isOn: $storageService.showAbsoluteChange)
        }
    }

    private var menuBarCard: some View {
        SettingsCard(title: "Menu bar") {
            SettingRow("Display") {
                DSPicker(options: [
                    ("pnl", "P&L (+321.09€)"),
                    ("pnlPercent", "P&L % (+2.3%)"),
                    ("pnlFull", "P&L + %"),
                    ("totalValue", "Total value"),
                    ("bestStock", "Best stock"),
                    ("worstStock", "Worst stock"),
                    ("bestWorst", "Best & Worst"),
                    ("portfolioRecap", "Portfolio recap"),
                    ("ticker", "Ticker (cycle watchlist)"),
                    ("tickerPortfolio", "Ticker + Portfolio"),
                    ("icon", "Icon only"),
                ], selection: $storageService.menuBarDisplay, width: 230)
            }
            SettingDivider()
            SettingRow("Percentage decimals", caption: "Digits after the decimal point (e.g. +2.34%)") {
                DSPicker(options: [(0, "0"), (1, "1"), (2, "2"), (3, "3"), (4, "4")],
                         selection: $storageService.percentDecimals, width: 110)
            }
            SettingDivider()
            SettingRow("Value decimals", caption: "Prices & amounts. Auto = extra precision for forex / sub-dollar") {
                DSPicker(options: [(-1, "Auto"), (0, "0"), (1, "1"), (2, "2"), (3, "3"), (4, "4")],
                         selection: $storageService.valueDecimals, width: 110)
            }
            SettingDivider()
            SettingToggle("Hide percentage change",
                          caption: "Show only price / value, no % in the menu bar",
                          isOn: $storageService.menuBarHidePercent)
            if storageService.menuBarDisplay == "ticker" || storageService.menuBarDisplay == "tickerPortfolio" {
                SettingDivider()
                SettingToggle("Show name instead of symbol",
                              caption: "\"S&P 500\" instead of \"^GSPC\"",
                              isOn: $storageService.tickerShowName)
                SettingDivider()
                SettingRow("Ticker order") {
                    DSPicker(options: [("manual", "As added"), ("type", "By type"), ("alpha", "Alphabetical")],
                             selection: $storageService.watchlistSort, width: 180)
                }
            }
            SettingDivider()
            SettingToggle("Use system text color",
                          caption: "Always readable; direction stays in + / − and ▲ ▼",
                          isOn: $storageService.menuBarUseSystemColor)
            if !storageService.menuBarUseSystemColor {
                SettingDivider()
                SettingRow("Gain color") {
                    DSColorWell(color: Binding(
                        get: { Color(nsColor: storageService.gainColor) },
                        set: { storageService.gainColorHex = $0.hexString }))
                }
                SettingDivider()
                SettingRow("Loss color") {
                    DSColorWell(color: Binding(
                        get: { Color(nsColor: storageService.lossColor) },
                        set: { storageService.lossColorHex = $0.hexString }))
                }
                SettingDivider()
                HStack {
                    Spacer()
                    Button("Reset to default green/red") {
                        storageService.gainColorHex = ""; storageService.lossColorHex = ""
                    }
                    .buttonStyle(.plain)
                    .font(.inter(11, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(DS.brand)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var notificationsCard: some View {
        SettingsCard(title: "Notifications") {
            SettingToggle("Mirror to a Discord/Slack webhook",
                          caption: "Price alerts and portfolio notifications are also sent there",
                          isOn: $storageService.discordEnabled)
            if storageService.discordEnabled {
                SettingDivider()
                let trimmed = storageService.discordWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.system(size: 10)).foregroundStyle(DS.inkTertiary)
                        TextField("https://discord.com/api/webhooks/…", text: $storageService.discordWebhookURL)
                            .textFieldStyle(.plain)
                            .font(.inter(11.5, relativeTo: .caption).monospacedDigit())
                            .focused($webhookFocused)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.cardAlt))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(webhookFocused ? DS.brand : .clear, lineWidth: 1.5))
                    .animation(.easeOut(duration: 0.15), value: webhookFocused)
                    HStack {
                        if !trimmed.isEmpty && !WebhookNotifier.isValid(trimmed) {
                            Text("Not a valid Discord or Slack webhook URL (must be https).")
                                .font(DS.micro).foregroundStyle(DS.down)
                        }
                        Spacer()
                        Button("Send test") {
                            NotificationManager.shared.send(title: "StockDock test", body: "Webhook is working ✅", sentiment: .positive)
                        }
                        .buttonStyle(.plain)
                        .font(.inter(11, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(WebhookNotifier.isValid(trimmed) ? DS.brand : DS.inkTertiary)
                        .disabled(!WebhookNotifier.isValid(trimmed))
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var alertsCard: some View {
        SettingsCard(title: "Price alerts") {
            ForEach(storageService.alerts) { alert in
                AlertRow(alert: alert)
                if alert.id != storageService.alerts.last?.id { SettingDivider() }
            }
            SettingDivider()
            HStack {
                Spacer()
                Button("Clear all alerts") { showClearAlerts = true }
                    .buttonStyle(.plain)
                    .font(.inter(11, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(DS.down)
            }
            .padding(.vertical, 6)
        }
    }

    private func portfolioNotifsCard(_ portfolios: [Portfolio]) -> some View {
        SettingsCard(title: "Portfolio notifications") {
            ForEach(portfolios) { portfolio in
                Text(portfolio.name)
                    .font(DS.bodyStrong).foregroundStyle(DS.inkSecondary)
                    .padding(.top, 4)
                ForEach(storageService.notifications(for: portfolio.id)) { n in
                    PortfolioNotifRow(portfolioId: portfolio.id, notification: n)
                }
                if portfolio.id != portfolios.last?.id { SettingDivider() }
            }
            SettingDivider()
            HStack {
                Spacer()
                Button("Clear all portfolio notifications") { showClearPortfolioNotifs = true }
                    .buttonStyle(.plain)
                    .font(.inter(11, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(DS.down)
            }
            .padding(.vertical, 6)
        }
    }

    private var appearanceCard: some View {
        SettingsCard(title: "Appearance") {
            SettingRow("Theme") {
                DSPicker(options: AppearanceMode.allCases.map { ($0, $0.label) },
                         selection: Binding(get: { storageService.appearanceMode },
                                            set: { storageService.appearanceMode = $0 }),
                         width: 160)
            }
            SettingDivider()
            SettingRow("Show News tab", caption: "The Home feed only fetches while open — no background use") {
                DSToggle(isOn: $storageService.showNewsTab)
            }
            SettingDivider()
            SettingRow("Font") {
                DSPicker(options: FontRegistration.availableFonts.map { ($0.family, $0.label) },
                         selection: $storageService.fontFamily, width: 200)
            }
            SettingDivider()
            SettingRow("Text size") {
                HStack(spacing: 10) {
                    Text("A").font(.inter(10, relativeTo: .caption)).foregroundStyle(DS.inkTertiary)
                    DSSlider(value: Binding(get: { Double(storageService.fontSizeLevel) },
                                            set: { storageService.fontSizeLevel = Int($0) }),
                             range: 7...13, step: 1, width: 160)
                    Text("A").font(.inter(15, weight: .bold, relativeTo: .body)).foregroundStyle(DS.inkTertiary)
                    Text("\(storageService.fontSizeLevel)")
                        .font(DS.figure).foregroundStyle(DS.inkSecondary)
                        .frame(width: 18, alignment: .trailing)
                }
            }
        }
    }

    private var aboutCard: some View {
        SettingsCard(title: "About") {
            SettingRow("Updates") {
                Button("Check for Updates…") {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    updaterViewModel.checkForUpdates()
                }
                .buttonStyle(.plain)
                .font(.inter(11.5, weight: .medium, relativeTo: .caption))
                .foregroundStyle(updaterViewModel.canCheckForUpdates ? DS.brand : DS.inkTertiary)
                .disabled(!updaterViewModel.canCheckForUpdates)
            }
            SettingDivider()
            SettingRow("StockDock is free and open source",
                       caption: "If it's useful to you, you can sponsor its development") {
                Button {
                    if let url = URL(string: "https://github.com/sponsors/simonsruggi") { NSWorkspace.shared.open(url) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill").font(.system(size: 9))
                        Text("Sponsor").font(.inter(11.5, weight: .semibold, relativeTo: .caption))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color(red: 0.86, green: 0.30, blue: 0.46)))
                }
                .buttonStyle(.plain)
            }
            SettingDivider()
            SettingRow("Reset", caption: "Portfolios and watchlist are not affected") {
                Button("Reset to Defaults…") { showResetAlert = true }
                    .buttonStyle(.plain)
                    .font(.inter(11.5, weight: .medium, relativeTo: .caption))
                    .foregroundStyle(DS.down)
            }
        }
    }
}

// MARK: - Settings building blocks

/// A premium card holding a stack of setting rows.
private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
                .padding(.bottom, 4)
            content
        }
        .padding(.horizontal, DS.pad)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard()
    }
}

/// Label (+ optional caption) on the left, control on the right.
private struct SettingRow<Control: View>: View {
    let label: String
    var caption: String? = nil
    @ViewBuilder var control: Control

    init(_ label: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label)).font(DS.body).foregroundStyle(DS.ink)
                if let caption {
                    Text(LocalizedStringKey(caption)).font(DS.micro).foregroundStyle(DS.inkTertiary)
                }
            }
            Spacer(minLength: 16)
            control
        }
        .padding(.vertical, 7)
    }
}

/// A toggle row in the app's emerald.
private struct SettingToggle: View {
    let label: String
    var caption: String? = nil
    @Binding var isOn: Bool

    init(_ label: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.caption = caption
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(label, caption: caption) {
            DSToggle(isOn: $isOn)
        }
    }
}

private struct SettingDivider: View {
    var body: some View {
        Divider().overlay(DS.hairline.opacity(0.6))
    }
}
