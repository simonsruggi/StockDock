import Foundation

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
            let priceStr = "\(currency)\(StorageService.formatNumber(quote.effectivePrice, decimals: 2))"
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
