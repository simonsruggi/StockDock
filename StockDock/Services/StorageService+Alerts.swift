import Foundation

extension StorageService {
    func addAlert(_ alert: PriceAlert) {
        alerts.append(alert)
    }

    /// Edits an alert's rule; a changed rule is a new target, so it is re-armed.
    func updateAlert(id: UUID, condition: AlertCondition, threshold: Double) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].condition = condition
        alerts[i].threshold = threshold
        alerts[i].isEnabled = true
        alerts[i].lastTriggeredAt = nil
    }

    func removeAlert(id: UUID) {
        alerts.removeAll { $0.id == id }
    }

    func removeAllAlerts() {
        alerts.removeAll()
    }

    func setAlertEnabled(id: UUID, enabled: Bool) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].isEnabled = enabled
        if enabled { alerts[i].lastTriggeredAt = nil }
    }

    /// Enables/disables several alerts in one mutation (group toggle in Settings).
    func setAlertsEnabled(ids: Set<UUID>, enabled: Bool) {
        var updated = alerts
        for i in updated.indices where ids.contains(updated[i].id) {
            updated[i].isEnabled = enabled
            if enabled { updated[i].lastTriggeredAt = nil }
        }
        alerts = updated
    }

    /// Marks an alert as fired: records the time and disables it (one-shot).
    func markAlertTriggered(id: UUID, at date: Date = Date()) {
        guard let i = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[i].isEnabled = false
        alerts[i].lastTriggeredAt = date
    }

    func alerts(for symbol: String) -> [PriceAlert] {
        alerts.filter { $0.symbol == symbol }
    }

    // MARK: - Portfolio notifications

    func notifications(for portfolioId: UUID) -> [PortfolioNotification] {
        portfolioNotifications[portfolioId.uuidString] ?? []
    }

    func addPortfolioNotification(_ notification: PortfolioNotification, to portfolioId: UUID) {
        portfolioNotifications[portfolioId.uuidString, default: []].append(notification)
    }

    func removeAllPortfolioNotifications() {
        portfolioNotifications = [:]
    }

    func removePortfolioNotification(id: UUID, from portfolioId: UUID) {
        portfolioNotifications[portfolioId.uuidString]?.removeAll { $0.id == id }
        if portfolioNotifications[portfolioId.uuidString]?.isEmpty == true {
            portfolioNotifications[portfolioId.uuidString] = nil
        }
    }

    func setPortfolioNotificationEnabled(id: UUID, in portfolioId: UUID, enabled: Bool) {
        guard let i = portfolioNotifications[portfolioId.uuidString]?.firstIndex(where: { $0.id == id }) else { return }
        portfolioNotifications[portfolioId.uuidString]?[i].isEnabled = enabled
        if enabled {
            portfolioNotifications[portfolioId.uuidString]?[i].lastStepUp = nil
            portfolioNotifications[portfolioId.uuidString]?[i].lastStepDown = nil
            portfolioNotifications[portfolioId.uuidString]?[i].lastDay = nil
        }
    }

    /// Persists the anti-spam high-water state after a notification fires (or primes silently).
    func updatePortfolioNotificationState(id: UUID, in portfolioId: UUID,
                                          lastStepUp: Double?, lastStepDown: Double?, lastDay: String?) {
        guard let i = portfolioNotifications[portfolioId.uuidString]?.firstIndex(where: { $0.id == id }) else { return }
        portfolioNotifications[portfolioId.uuidString]?[i].lastStepUp = lastStepUp
        portfolioNotifications[portfolioId.uuidString]?[i].lastStepDown = lastStepDown
        portfolioNotifications[portfolioId.uuidString]?[i].lastDay = lastDay
    }

    // MARK: - Portfolio snapshots

    func snapshots(for portfolioId: UUID) -> [PortfolioSnapshot] {
        portfolioSnapshots[portfolioId.uuidString] ?? []
    }

    /// Records a portfolio's value/cost for today, keeping one snapshot per day
    /// (today's is replaced so the latest intraday value wins). The date is
    /// normalized to the start of the local day. No-ops for an empty portfolio so
    /// the history doesn't fill with zeros before any holdings exist.
    func recordSnapshot(for portfolioId: UUID, totalValue: Double, totalCost: Double,
                        now: Date = Date(), calendar: Calendar = .current) {
        guard totalValue != 0 || totalCost != 0 else { return }
        let snapshot = PortfolioSnapshot(date: calendar.startOfDay(for: now),
                                         totalValue: totalValue, totalCost: totalCost)
        let key = portfolioId.uuidString
        portfolioSnapshots[key] = SnapshotLog.upsert(snapshot, into: portfolioSnapshots[key] ?? [], calendar: calendar)
    }
}
