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
            let live = livePrice(for: quote)
            let fires: Bool
            if let live {
                fires = AlertEvaluator.shouldFire(condition: alert.condition,
                                                  threshold: alert.threshold,
                                                  isEnabled: alert.isEnabled,
                                                  price: live.price,
                                                  changePercent: live.changePercent,
                                                  fiftyTwoWeekHigh: quote.fiftyTwoWeekHigh,
                                                  fiftyTwoWeekLow: quote.fiftyTwoWeekLow)
            } else {
                fires = AlertEvaluator.shouldFire(alert, quote: quote)
            }
            guard fires else { continue }

            let currency = StorageService.currencySymbol(for: quote.currency)
            let shownPrice = live?.price ?? quote.effectivePrice
            let priceStr = "\(currency)\(StorageService.formatNumber(shownPrice, decimals: 2))"
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

    /// Off-hours the price the user sees is Hyperliquid's 24/7 one, so alerts
    /// are evaluated against that same price and daily change.
    private func livePrice(for quote: StockQuote) -> (price: Double, changePercent: Double)? {
        let hl = HyperliquidService.shared
        guard let allHours = hl.quote(for: quote) else { return nil }
        return (allHours.price, hl.liveChangePercent(for: quote, extendedHours: storage.showExtendedHours))
    }
}
