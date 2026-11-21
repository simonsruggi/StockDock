import SwiftUI

extension SettingsView {
    private var trimmedWebhook: String {
        storageService.discordWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var portfoliosWithNotifications: [Portfolio] {
        storageService.portfolios.filter { !storageService.notifications(for: $0.id).isEmpty }
    }

    var notificationsGroup: some View {
        SettingsGroup(title: "Notifications", icon: "bell", isExpanded: $groupNotifications) {
            SettingToggle("Mirror to a Discord/Slack webhook", isOn: $storageService.discordEnabled).searchAnchor("webhook")
            if storageService.discordEnabled { webhookField }

            SettingSubheader("Price alerts").searchAnchor("priceAlerts")
            if storageService.alerts.isEmpty {
                emptyLine("No alerts. Right-click a stock in the watchlist to add one.")
            } else {
                AlertGroupList()
                trailingAction("Clear all", tint: DS.down) { showClearAlerts = true }
            }

            SettingSubheader("Portfolio notifications").searchAnchor("portfolioNotifications")
            let portfolios = portfoliosWithNotifications
            if portfolios.isEmpty {
                emptyLine("None. Right-click a portfolio → “Notifications…” to add one.")
            } else {
                ForEach(portfolios) { portfolio in
                    Text(portfolio.name)
                        .font(DS.bodyStrong).foregroundStyle(DS.inkSecondary)
                        .padding(.top, 4)
                    ForEach(storageService.notifications(for: portfolio.id)) { n in
                        PortfolioNotifRow(portfolioId: portfolio.id, notification: n)
                    }
                }
                trailingAction("Clear all", tint: DS.down) { showClearPortfolioNotifs = true }
            }
        }
    }

    private var webhookField: some View {
        let valid = WebhookNotifier.isValid(trimmedWebhook)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "link").font(.system(size: 10)).foregroundStyle(DS.inkTertiary)
                TextField("https://discord.com/api/webhooks/…", text: $storageService.discordWebhookURL)
                    .textFieldStyle(.plain)
                    .font(.inter(11.5, relativeTo: .caption))
                    .focused($webhookFocused)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.cardAlt))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(webhookFocused ? DS.brand : DS.hairline, lineWidth: webhookFocused ? 1.5 : 1))
            HStack {
                if !trimmedWebhook.isEmpty && !valid {
                    Text("Not a valid Discord or Slack webhook URL (must be https).")
                        .font(DS.micro).foregroundStyle(DS.down)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                SettingLinkButton("Send test", enabled: valid) {
                    NotificationManager.shared.send(title: "StockDock test", body: "Webhook is working ✅", sentiment: .positive)
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(DS.caption).foregroundStyle(DS.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }

    private func trailingAction(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            SettingLinkButton(title, tint: tint, action: action)
        }
        .padding(.vertical, 8)
    }
}
