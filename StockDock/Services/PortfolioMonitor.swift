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
        var holdings: [HoldingLine] = []  // per-symbol breakdown, sorted by day impact
        var hasData = false

        var dayChangePercent: Double { prevValue > 0 ? (dayChange / prevValue) * 100 : 0 }
    }

    /// One line of the per-holding breakdown shown in notification bodies.
    private struct HoldingLine {
        let symbol: String
        let changePercent: Double    // today's % change for the symbol
        let value: Double            // holding market value, in preferred currency
        let dayContribution: Double  // today's gain/loss this symbol added, in preferred currency
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
        // High-water marks reset each calendar day.
        let scopedUp = (n.lastDay == today) ? n.lastStepUp : nil
        let scopedDown = (n.lastDay == today) ? n.lastStepDown : nil
        guard let step = PortfolioAlertEvaluator.crossingStep(value: value, threshold: n.threshold,
                                                              lastUp: scopedUp, lastDown: scopedDown) else { return }

        let up = step > 0
        let pctStr = String(format: "%+.2f%%", metrics.dayChangePercent)
        let absStr = StorageService.formatAmount(metrics.dayChange, symbol: currSym, signed: true)
        var body = "Today: \(absStr) (\(pctStr)) — value \(StorageService.formatAmount(metrics.totalValue, symbol: currSym))"
        let lines = breakdownLines(metrics: metrics, currSym: currSym)
        if !lines.isEmpty { body += "\n\n" + lines.joined(separator: "\n") }
        notifier.send(
            title: "\(portfolio.name) \(up ? "📈" : "📉") \(isPercent ? pctStr : absStr) today",
            body: body,
            identifier: "pf-\(n.id.uuidString)-\(today)-\(Int(step))",
            sentiment: up ? .positive : .negative
        )
        // Advance only the side that just fired; carry the other side's high-water within the day.
        let newUp = up ? step : scopedUp
        let newDown = up ? scopedDown : step
        storage.updatePortfolioNotificationState(id: n.id, in: portfolio.id,
                                                 lastStepUp: newUp, lastStepDown: newDown, lastDay: today)
    }

    private func evaluateMilestone(_ n: PortfolioNotification, portfolio: Portfolio, metrics: Metrics, currSym: String) {
        guard let milestone = PortfolioAlertEvaluator.milestoneCrossed(totalValue: metrics.totalValue, step: n.threshold,
                                                                       highest: n.lastStepUp, lowest: n.lastStepDown) else { return }
        // First observation primes both bounds silently — avoids a spurious "reached X" on setup.
        guard n.lastStepUp != nil || n.lastStepDown != nil else {
            storage.updatePortfolioNotificationState(id: n.id, in: portfolio.id,
                                                     lastStepUp: milestone, lastStepDown: milestone, lastDay: n.lastDay)
            return
        }
        let up = milestone > (n.lastStepUp ?? milestone)
        notifier.send(
            title: "\(portfolio.name) \(up ? "🎯" : "⚠️") \(StorageService.formatAmount(milestone, symbol: currSym, decimals: 0))",
            body: "Total value \(up ? "crossed above" : "dropped below") \(StorageService.formatAmount(milestone, symbol: currSym, decimals: 0)) — now \(StorageService.formatAmount(metrics.totalValue, symbol: currSym))",
            identifier: "pf-\(n.id.uuidString)-ms-\(Int(milestone))",
            sentiment: up ? .positive : .negative
        )
        // Widen the bounds: push the high up or the low down.
        let newHigh = max(milestone, n.lastStepUp ?? milestone)
        let newLow = min(milestone, n.lastStepDown ?? milestone)
        storage.updatePortfolioNotificationState(id: n.id, in: portfolio.id,
                                                 lastStepUp: newHigh, lastStepDown: newLow, lastDay: n.lastDay)
    }

    private func evaluateSummary(_ n: PortfolioNotification, portfolio: Portfolio, today: String, hour: Int, metrics: Metrics, currSym: String) {
        let afterClose = Double(hour) >= n.threshold
        guard PortfolioAlertEvaluator.shouldFireSummary(today: today, lastDay: n.lastDay, isAfterClose: afterClose) else { return }
        let up = metrics.dayChange >= 0
        var body = "Value \(StorageService.formatAmount(metrics.totalValue, symbol: currSym)) — today \(StorageService.formatAmount(metrics.dayChange, symbol: currSym, signed: true)) (\(String(format: "%+.2f%%", metrics.dayChangePercent)))"
        let lines = breakdownLines(metrics: metrics, currSym: currSym)
        if !lines.isEmpty { body += "\n\n" + lines.joined(separator: "\n") }
        notifier.send(
            title: "\(portfolio.name) — daily summary",
            body: body,
            identifier: "pf-\(n.id.uuidString)-sum-\(today)",
            sentiment: up ? .positive : .negative
        )
        storage.updatePortfolioNotificationState(id: n.id, in: portfolio.id,
                                                 lastStepUp: n.lastStepUp, lastStepDown: n.lastStepDown, lastDay: today)
    }

    // MARK: - Metrics

    private func computeMetrics(_ portfolio: Portfolio) -> Metrics {
        var m = Metrics()
        // Aggregate by symbol so a portfolio holding the same stock in multiple lots
        // shows a single combined line.
        var acc: [String: (changePercent: Double, value: Double, contribution: Double)] = [:]
        for holding in portfolio.holdings {
            guard let quote = stockService.quotes[holding.symbol] else { continue }
            m.hasData = true
            let rate = stockService.rate(from: quote.currency)
            let displayPrice = quote.displayPrice(extendedHours: storage.showExtendedHours)
            let value = holding.marketValue(currentPrice: displayPrice) * rate
            // Today's change uses the regular-session change per share.
            let contribution = holding.quantity * quote.change * rate
            let prevClose = quote.price - quote.change
            m.totalValue += value
            m.dayChange += contribution
            m.prevValue += holding.quantity * prevClose * rate
            var entry = acc[quote.symbol] ?? (quote.changePercent, 0, 0)
            entry.changePercent = quote.changePercent
            entry.value += value
            entry.contribution += contribution
            acc[quote.symbol] = entry
        }
        m.holdings = acc
            .map { HoldingLine(symbol: $0.key, changePercent: $0.value.changePercent,
                               value: $0.value.value, dayContribution: $0.value.contribution) }
            .sorted { abs($0.dayContribution) > abs($1.dayContribution) }
        return m
    }

    /// Builds the per-holding breakdown lines (symbol · today's % · value), biggest
    /// daily movers first. Capped so notification bodies stay readable.
    private func breakdownLines(metrics: Metrics, currSym: String, limit: Int = 12) -> [String] {
        guard !metrics.holdings.isEmpty else { return [] }
        var lines = metrics.holdings.prefix(limit).map { h -> String in
            let arrow = h.changePercent >= 0 ? "▲" : "▼"
            let pct = String(format: "%+.2f%%", h.changePercent)
            let val = StorageService.formatAmount(h.value, symbol: currSym)
            return "\(arrow) \(h.symbol)  \(pct)  ·  \(val)"
        }
        if metrics.holdings.count > limit {
            lines.append("…and \(metrics.holdings.count - limit) more")
        }
        return lines
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
