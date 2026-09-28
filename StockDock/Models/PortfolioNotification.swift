import Foundation

/// A per-portfolio notification rule. Unlike one-shot `PriceAlert`s these are recurring;
/// `lastStep`/`lastDay` hold the anti-spam state so each event fires at most once.
struct PortfolioNotification: Identifiable, Codable, Equatable {
    var id: UUID
    var mode: PortfolioNotificationMode
    var threshold: Double
    var isEnabled: Bool
    /// High-water mark on the **up** side: highest positive step notified today
    /// (dailyPercent/dailyAbsolute, scoped to `lastDay`) or the highest milestone reached.
    var lastStepUp: Double?
    /// High-water mark on the **down** side: lowest negative step notified today
    /// (scoped to `lastDay`) or the lowest milestone reached.
    var lastStepDown: Double?
    /// yyyy-MM-dd of the last fire — resets daily steps and gates the daily summary.
    var lastDay: String?

    init(id: UUID = UUID(),
         mode: PortfolioNotificationMode,
         threshold: Double,
         isEnabled: Bool = true,
         lastStepUp: Double? = nil,
         lastStepDown: Double? = nil,
         lastDay: String? = nil) {
        self.id = id
        self.mode = mode
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.lastStepUp = lastStepUp
        self.lastStepDown = lastStepDown
        self.lastDay = lastDay
    }
}
