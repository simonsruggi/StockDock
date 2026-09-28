import SwiftUI

/// A single portfolio-notification row in Settings: enable toggle, description and delete.
struct PortfolioNotifRow: View {
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
            return "Every ±\(currencySymbol)\(String(format: "%g", n.threshold)) move today"
        case .milestone:
            return "Every \(currencySymbol)\(String(format: "%g", n.threshold)) crossed"
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
