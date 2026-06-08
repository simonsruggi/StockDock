import Foundation
import UserNotifications

/// Thin wrapper around UNUserNotificationCenter for local alert notifications.
/// Guarded so it is a no-op when running without a proper app bundle (e.g. `swift run`
/// in development), where UNUserNotificationCenter.current() would crash.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    /// True only when running as a bundled, identifiable app where notifications work.
    private let isAvailable: Bool

    private init() {
        isAvailable = Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("[Notifications] authorization error: %@", error.localizedDescription) }
        }
    }

    /// - Parameter sentiment: drives the Discord embed color (positive/negative/neutral).
    func send(title: String, body: String, identifier: String = UUID().uuidString, sentiment: Sentiment = .neutral) {
        // Forward to the configured webhook regardless of bundle state (works in dev too).
        forwardToWebhook(title: title, body: body, sentiment: sentiment)

        guard isAvailable else {
            NSLog("[Notifications] (dev no-op) %@ — %@", title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("[Notifications] add error: %@", error.localizedDescription) }
        }
    }

    /// Tone of a notification — maps to a Discord embed color.
    enum Sentiment {
        case positive, negative, neutral

        var color: Int {
            switch self {
            case .positive: return WebhookNotifier.Color.green
            case .negative: return WebhookNotifier.Color.red
            case .neutral: return WebhookNotifier.Color.neutral
            }
        }
    }

    private func forwardToWebhook(title: String, body: String, sentiment: Sentiment) {
        let storage = StorageService.shared
        guard storage.discordEnabled else { return }
        let url = storage.discordWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WebhookNotifier.isValid(url) else { return }
        Task.detached {
            await WebhookNotifier.send(to: url, title: title, body: body, color: sentiment.color)
        }
    }
}

/// Evaluates the user's alerts against the latest quotes and fires one-shot
/// notifications. Disabling fired alerts (via StorageService) prevents repeats.
@MainActor
final class AlertMonitor {
    private let storage: StorageService
    private let notifier: NotificationManager

    init(storage: StorageService, notifier: NotificationManager? = nil) {
        self.storage = storage
        self.notifier = notifier ?? .shared
    }

    /// Check all enabled alerts against the given quotes; fire + disable those that match.
    func check(quotes: [String: StockQuote]) {
        for alert in storage.alerts where alert.isEnabled {
            guard let quote = quotes[alert.symbol] else { continue }
            guard AlertEvaluator.shouldFire(alert, quote: quote) else { continue }

            let currency = StorageService.currencySymbol(for: quote.currency)
            let priceStr = "\(currency)\(String(format: "%.2f", quote.effectivePrice))"
            let sentiment: NotificationManager.Sentiment
            switch alert.condition {
            case .priceAbove, .dailyChangeUp, .near52WeekHigh: sentiment = .positive
            case .priceBelow, .dailyChangeDown, .near52WeekLow: sentiment = .negative
            }
            notifier.send(
                title: "\(alert.symbol) alert",
                body: "\(AlertEvaluator.describe(alert, currencySymbol: currency)) — now \(priceStr)",
                identifier: alert.id.uuidString,
                sentiment: sentiment
            )
            storage.markAlertTriggered(id: alert.id)
        }
    }
}
