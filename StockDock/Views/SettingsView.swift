import Sparkle
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @State private var showResetAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Stock Price Currency
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stock Price Currency")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Picker("Price currency", selection: $storageService.stockPriceCurrency) {
                        Text("Original").tag("")
                        ForEach(StorageService.supportedCurrencies, id: \.self) { code in
                            Text("\(StorageService.currencySymbol(for: code)) \(code)")
                                .tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: storageService.stockPriceCurrency) {
                        stockService.exchangeRates.removeAll()
                        Task {
                            await stockService.refreshAll(storageService: storageService)
                        }
                    }
                    Text(storageService.stockPriceCurrency.isEmpty
                         ? "Prices shown in their native currency"
                         : "All prices converted to \(storageService.stockPriceCurrency)")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Portfolio Currency
                VStack(alignment: .leading, spacing: 6) {
                    Text("Portfolio Currency")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Picker("Portfolio currency", selection: $storageService.preferredCurrency) {
                        ForEach(StorageService.supportedCurrencies, id: \.self) { code in
                            Text("\(StorageService.currencySymbol(for: code)) \(code)")
                                .tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: storageService.preferredCurrency) {
                        stockService.exchangeRates.removeAll()
                        Task {
                            await stockService.refreshAll(storageService: storageService)
                        }
                    }
                    Text("Portfolio totals and P&L converted to \(storageService.preferredCurrency)")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Extended Hours
                VStack(alignment: .leading, spacing: 6) {
                    Text("Market Hours")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Toggle("Show extended hours (Pre/Post)", isOn: $storageService.showExtendedHours)
                        .toggleStyle(.switch)
                    Text("Show pre-market and after-hours prices")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Watchlist Display
                VStack(alignment: .leading, spacing: 6) {
                    Text("Watchlist Display")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Toggle("Company name", isOn: $storageService.showCompanyName)
                        .toggleStyle(.switch)
                    Toggle("Day range (low – high)", isOn: $storageService.showDayRange)
                        .toggleStyle(.switch)
                    Toggle("52-week range bar", isOn: $storageService.show52WeekBar)
                        .toggleStyle(.switch)
                    Toggle("Absolute change value", isOn: $storageService.showAbsoluteChange)
                        .toggleStyle(.switch)
                    Text("Choose which details appear in each watchlist row")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Menu Bar Display
                VStack(alignment: .leading, spacing: 6) {
                    Text("Menu Bar Display")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Picker("Display", selection: $storageService.menuBarDisplay) {
                        Text("P&L (+321.09€)").tag("pnl")
                        Text("P&L % (+2.3%)").tag("pnlPercent")
                        Text("P&L + % (+321.09€ +2.3%)").tag("pnlFull")
                        Text("Total Value (14396.67€)").tag("totalValue")
                        Text("Best Stock (▲ AAPL +1.2%)").tag("bestStock")
                        Text("Worst Stock (▼ TSLA -0.8%)").tag("worstStock")
                        Text("Best & Worst").tag("bestWorst")
                        Text("Portfolio (14396.67€ +1.2%)").tag("portfolioRecap")
                        Text("Ticker (cycle watchlist)").tag("ticker")
                        Text("Icon Only").tag("icon")
                    }
                    .pickerStyle(.menu)
                    Text("Choose what to show in the menu bar")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }
                Divider()

                // MARK: - Notifications
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notifications")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))

                    // Channels (Discord / Slack webhook)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Channels")
                            .font(.inter(11, weight: .semibold, relativeTo: .subheadline))
                            .foregroundColor(.secondary)
                        Toggle("Mirror notifications to a Discord/Slack webhook", isOn: $storageService.discordEnabled)
                            .toggleStyle(.switch)
                        TextField("https://discord.com/api/webhooks/… or hooks.slack.com/…", text: $storageService.discordWebhookURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.inter(10, relativeTo: .caption))
                            .disabled(!storageService.discordEnabled)
                        let trimmed = storageService.discordWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        if storageService.discordEnabled && !trimmed.isEmpty && !WebhookNotifier.isValid(trimmed) {
                            Text("Not a valid Discord or Slack webhook URL (must be https).")
                                .font(.inter(10, relativeTo: .caption))
                                .foregroundColor(.red)
                        } else {
                            Text("Price alerts and portfolio notifications are also sent here.")
                                .font(.inter(10, relativeTo: .caption))
                                .foregroundColor(.secondary)
                        }
                        Button("Send test") {
                            NotificationManager.shared.send(
                                title: "StockDock test",
                                body: "Webhook is working ✅",
                                sentiment: .positive)
                        }
                        .controlSize(.small)
                        .disabled(!storageService.discordEnabled || !WebhookNotifier.isValid(trimmed))
                    }

                    // Price alerts
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Price alerts")
                            .font(.inter(11, weight: .semibold, relativeTo: .subheadline))
                            .foregroundColor(.secondary)
                        if storageService.alerts.isEmpty {
                            Text("No alerts. Right-click a stock in the watchlist to add one.")
                                .font(.inter(10, relativeTo: .caption))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(storageService.alerts) { alert in
                                AlertRow(alert: alert)
                            }
                        }
                    }

                    // Portfolio notifications
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Portfolio notifications")
                            .font(.inter(11, weight: .semibold, relativeTo: .subheadline))
                            .foregroundColor(.secondary)
                        let withNotifs = storageService.portfolios.filter {
                            !storageService.notifications(for: $0.id).isEmpty
                        }
                        if withNotifs.isEmpty {
                            Text("None. Right-click a portfolio → “Notifications…” to add one.")
                                .font(.inter(10, relativeTo: .caption))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(withNotifs) { portfolio in
                                Text(portfolio.name)
                                    .font(.inter(10, weight: .medium, relativeTo: .caption))
                                ForEach(storageService.notifications(for: portfolio.id)) { n in
                                    PortfolioNotifRow(portfolioId: portfolio.id, notification: n)
                                }
                            }
                        }
                    }
                }

                Divider()

                // MARK: - Font
                VStack(alignment: .leading, spacing: 6) {
                    Text("Font")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Picker("Font family", selection: $storageService.fontFamily) {
                        ForEach(FontRegistration.availableFonts, id: \.family) { font in
                            Text(font.label)
                                .font(.custom(font.family, size: 13))
                                .tag(font.family)
                        }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        Text("A")
                            .font(.inter(10, relativeTo: .caption))
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { Double(storageService.fontSizeLevel) },
                            set: { storageService.fontSizeLevel = Int($0) }
                        ), in: 7...13, step: 1)
                        Text("A")
                            .font(.inter(18, weight: .bold, relativeTo: .title2))
                            .foregroundColor(.secondary)
                    }
                    Text("Size: \(storageService.fontSizeLevel)")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Updates
                VStack(alignment: .leading, spacing: 6) {
                    Text("Updates")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Button("Check for Updates...") {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reset")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Button("Reset to Default Settings") {
                        showResetAlert = true
                    }
                    .foregroundColor(.red)
                    Text("This will not erase your portfolios or watchlist")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .alert("Reset Settings", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                storageService.resetToDefaults()
                Task {
                    stockService.exchangeRates.removeAll()
                    await stockService.refreshAll(storageService: storageService)
                }
            }
        } message: {
            Text("This will reset all settings to their defaults. Your portfolios and watchlist will not be affected.")
        }
    }

}

/// A single alert row in Settings: enable/re-arm toggle, description and delete.
private struct AlertRow: View {
    @EnvironmentObject var storageService: StorageService
    let alert: PriceAlert

    private var currencySymbol: String {
        StorageService.currencySymbol(for: StockService.shared.quotes[alert.symbol]?.currency
            ?? storageService.preferredCurrency)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: alert.condition.systemImage)
                .font(.inter(10, relativeTo: .caption))
                .foregroundColor(alert.isEnabled ? .accentColor : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.symbol)
                    .font(.inter(12, weight: .semibold, relativeTo: .body))
                Text(AlertEvaluator.describe(alert, currencySymbol: currencySymbol))
                    .font(.inter(9, relativeTo: .caption2))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !alert.isEnabled {
                Text("triggered")
                    .font(.inter(8, weight: .semibold, relativeTo: .caption2))
                    .foregroundColor(.orange)
            }
            Toggle("", isOn: Binding(
                get: { alert.isEnabled },
                set: { storageService.setAlertEnabled(id: alert.id, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(alert.isEnabled ? "Enabled" : "Re-arm alert")
            Button(action: { storageService.removeAlert(id: alert.id) }) {
                Image(systemName: "trash")
                    .font(.inter(10, relativeTo: .caption))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

/// A single portfolio-notification row in Settings: enable toggle, description and delete.
private struct PortfolioNotifRow: View {
    @EnvironmentObject var storageService: StorageService
    let portfolioId: UUID
    let notification: PortfolioNotification

    private var currencySymbol: String {
        StorageService.currencySymbol(for: storageService.preferredCurrency)
    }

    private var description: String {
        let n = notification
        switch n.mode {
        case .dailyPercent:
            return "Every ±\(String(format: "%g", n.threshold))% move today"
        case .dailyAbsolute:
            return "Every ±\(String(format: "%g", n.threshold))\(currencySymbol) move today"
        case .milestone:
            return "Every \(String(format: "%g", n.threshold))\(currencySymbol) crossed"
        case .dailySummary:
            return "Daily after \(String(format: "%.0f", n.threshold)):00"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notification.mode.systemImage)
                .font(.inter(10, relativeTo: .caption))
                .foregroundColor(notification.isEnabled ? .accentColor : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(notification.mode.label)
                    .font(.inter(12, weight: .semibold, relativeTo: .body))
                Text(description)
                    .font(.inter(9, relativeTo: .caption2))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { notification.isEnabled },
                set: { storageService.setPortfolioNotificationEnabled(id: notification.id, in: portfolioId, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            Button(action: { storageService.removePortfolioNotification(id: notification.id, from: portfolioId) }) {
                Image(systemName: "trash")
                    .font(.inter(10, relativeTo: .caption))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}
