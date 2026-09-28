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

    /// Last delivery time per notification identifier — backs the burst de-duplicator so a
    /// logic regression can never spam the *same* event at WebSocket tick rate.
    private var lastSent: [String: Date] = [:]

    /// Minimum gap before the exact same identifier may fire again. Distinct events use distinct
    /// identifiers, so this only ever swallows rapid duplicates — never a genuinely new alert.
    private static let dedupWindow: TimeInterval = 120

    private init() {
        isAvailable = Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorization() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("[Notifications] authorization error: %@", error.localizedDescription) }
        }
    }

    /// Pure burst de-duplication: deliver when the identifier has never fired, or last fired
    /// at least `window` ago. Keeps the spam guard testable without a live notification center.
    nonisolated static func shouldDeliver(identifier: String, now: Date, lastSent: Date?, window: TimeInterval) -> Bool {
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= window
    }

    /// - Parameter sentiment: drives the Discord embed color (positive/negative/neutral).
    func send(title: String, body: String, identifier: String = UUID().uuidString, sentiment: Sentiment = .neutral) {
        let now = Date()
        guard Self.shouldDeliver(identifier: identifier, now: now, lastSent: lastSent[identifier], window: Self.dedupWindow) else {
            return
        }
        lastSent[identifier] = now

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
