import Foundation

/// Evaluates each portfolio's recurring notifications against live quotes and fires
/// macOS + webhook notifications. Anti-spam state is persisted via StorageService so
/// each event notifies at most once (per step / per milestone / per day).
@MainActor
final class PortfolioMonitor {
    private let storage: StorageService
    private let stockService: StockService
    private let notifier: NotificationManager

    init(storage: StorageService, stockService: StockService, notifier: NotificationManager? = nil) {
        self.storage = storage
        self.stockService = stockService
        self.notifier = notifier ?? .shared
    }

    /// Per-portfolio aggregated figures, all in the preferred currency.
    private struct Metrics {
        var totalValue = 0.0
        var dayChange = 0.0          // today's gain/loss (absolute)
        var prevValue = 0.0          // total value at yesterday's close
        var topMoverSymbol = ""
        var topMoverPercent = 0.0
        var hasData = false

        var dayChangePercent: Double { prevValue > 0 ? (dayChange / prevValue) * 100 : 0 }
    }

    func check(now: Date = Date()) {
        guard !storage.portfolioNotifications.isEmpty else { return }
        let today = Self.dayKey(now)
        let hour = Calendar.current.component(.hour, from: now)
        let currSym = StorageService.currencySymbol(for: storage.preferredCurrency)

        for portfolio in storage.portfolios {
            let notifs = storage.notifications(for: portfolio.id)
            guard !notifs.isEmpty else { continue }
            let metrics = computeMetrics(portfolio)
            guard metrics.hasData else { continue }

            for n in notifs where n.isEnabled {
                switch n.mode {
                case .dailyPercent:
                    evaluateDailyStep(n, portfolio: portfolio, today: today,
                                      value: metrics.dayChangePercent, metrics: metrics, currSym: currSym, isPercent: true)
                case .dailyAbsolute:
                    evaluateDailyStep(n, portfolio: portfolio, today: today,
                                      value: metrics.dayChange, metrics: metrics, currSym: currSym, isPercent: false)
                case .milestone:
                    evaluateMilestone(n, portfolio: portfolio, metrics: metrics, currSym: currSym)
                case .dailySummary:
                    evaluateSummary(n, portfolio: portfolio, today: today, hour: hour, metrics: metrics, currSym: currSym)
                }
            }
        }
    }

    // MARK: - Per-mode evaluation

    private func evaluateDailyStep(_ n: PortfolioNotification, portfolio: Portfolio, today: String,
                                   value: Double, metrics: Metrics, currSym: String, isPercent: Bool) {
        // Steps reset each calendar day.
        let scopedLast = (n.lastDay == today) ? n.lastStep : nil
        guard let step = PortfolioAlertEvaluator.crossingStep(value: value, threshold: n.threshold, lastStep: scopedLast) else { return }

        let up = step > 0
        let pctStr = String(format: "%+.2f%%", metrics.dayChangePercent)
        let absStr = StorageService.formatAmount(metrics.dayChange, symbol: currSym, signed: true)
        let body = "Today: \(absStr) (\(pctStr)) — value \(StorageService.formatAmount(metrics.totalValue, symbol: currSym))"
        notifier.send(
            title: "\(portfolio.name) \(up ? "📈" : "📉") \(isPercent ? pctStr : absStr) today",
            body: body,
            identifier: "pf-\(n.id.uuidString)-\(today)-\(Int(step))",
            sentiment: up ? .positive : .negative
        )
        storage.updatePortfolioNotificationState(id: n.id, in: portfolio.id, lastStep: step, lastDay: today)
    }

    private func evaluateMilestone(_ n: PortfolioNotification, portfolio: Portfolio, metrics: Metrics, currSym: String) {
        guard let milestone = PortfolioAlertEvaluator.milestoneCrossed(totalValue: metrics.totalValue, step: n.threshold, lastMilestone: n.lastStep) else { return }
        // First observation primes the state silently — avoids a spurious "reached X" on setup.
        guard let last = n.lastStep else {
            storage.updatePortfolioNotificationState(id: n.id, in: portfolio.id, lastStep: milestone, lastDay: n.lastDay)
            return
        }
        let up = milestone > last
        notifier.send(
            title: "\(portfolio.name) \(up ? "🎯" : "⚠️") \(StorageService.formatAmount(milestone, symbol: currSym, decimals: 0))",
            body: "Total value \(up ? "crossed above" : "dropped below") \(StorageService.formatAmount(milestone, symbol: currSym, decimals: 0)) — now \(StorageService.formatAmount(metrics.totalValue, symbol: currSym))",
            identifier: "pf-\(n.id.uuidString)-ms-\(Int(milestone))",
            sentiment: up ? .positive : .negative
        )
        storage.updatePortfolioNotificationState(id: n.id, in: portfolio.id, lastStep: milestone, lastDay: n.lastDay)
    }

    private func evaluateSummary(_ n: PortfolioNotification, portfolio: Portfolio, today: String, hour: Int, metrics: Metrics, currSym: String) {
        let afterClose = Double(hour) >= n.threshold
        guard PortfolioAlertEvaluator.shouldFireSummary(today: today, lastDay: n.lastDay, isAfterClose: afterClose) else { return }
        let up = metrics.dayChange >= 0
        var body = "Value \(StorageService.formatAmount(metrics.totalValue, symbol: currSym)) — today \(StorageService.formatAmount(metrics.dayChange, symbol: currSym, signed: true)) (\(String(format: "%+.2f%%", metrics.dayChangePercent)))"
        if !metrics.topMoverSymbol.isEmpty {
            body += "\nTop mover: \(metrics.topMoverSymbol) \(String(format: "%+.2f%%", metrics.topMoverPercent))"
        }
        notifier.send(
            title: "\(portfolio.name) — daily summary",
            body: body,
            identifier: "pf-\(n.id.uuidString)-sum-\(today)",
            sentiment: up ? .positive : .negative
        )
        storage.updatePortfolioNotificationState(id: n.id, in: portfolio.id, lastStep: n.lastStep, lastDay: today)
    }

    // MARK: - Metrics

    private func computeMetrics(_ portfolio: Portfolio) -> Metrics {
        var m = Metrics()
        for holding in portfolio.holdings {
            guard let quote = stockService.quotes[holding.symbol] else { continue }
            m.hasData = true
            let rate = stockService.rate(from: quote.currency)
            let displayPrice = quote.displayPrice(extendedHours: storage.showExtendedHours)
            m.totalValue += holding.marketValue(currentPrice: displayPrice) * rate
            // Today's change uses the regular-session change per share.
            m.dayChange += holding.quantity * quote.change * rate
            let prevClose = quote.price - quote.change
            m.prevValue += holding.quantity * prevClose * rate
            if abs(quote.changePercent) > abs(m.topMoverPercent) {
                m.topMoverPercent = quote.changePercent
                m.topMoverSymbol = quote.symbol
            }
        }
        return m
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
