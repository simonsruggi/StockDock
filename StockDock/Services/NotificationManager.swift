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

    func send(title: String, body: String, identifier: String = UUID().uuidString) {
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
            let priceStr = String(format: "%.2f %@", quote.effectivePrice, currency)
            notifier.send(
                title: "\(alert.symbol) alert",
                body: "\(AlertEvaluator.describe(alert, currencySymbol: currency)) — now \(priceStr)",
                identifier: alert.id.uuidString
            )
            storage.markAlertTriggered(id: alert.id)
        }
    }
}
