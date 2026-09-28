import Foundation

struct Holding: Identifiable, Codable {
    var id: UUID
    var symbol: String
    /// Number of shares. Negative means a short position (gated behind the
    /// "Advanced" setting in the UI).
    var quantity: Double
    var avgPrice: Double
    /// Purchase date for historical exchange rate in cost basis calculation
    var purchaseDate: Date?
    /// Leverage multiplier applied to P&L and exposure (1.0 = unlevered).
    /// Optional so portfolios saved before 1.7.1 decode cleanly as unlevered.
    var leverage: Double?

    init(id: UUID = UUID(), symbol: String, quantity: Double, avgPrice: Double, purchaseDate: Date? = nil, leverage: Double? = nil) {
        self.id = id
        self.symbol = symbol
        self.quantity = quantity
        self.avgPrice = avgPrice
        self.purchaseDate = purchaseDate
        self.leverage = leverage
    }

    /// Leverage multiplier, defaulting to 1x when unset or invalid.
    var effectiveLeverage: Double {
        guard let l = leverage, l > 0 else { return 1 }
        return l
    }

    /// True for a short position (negative quantity).
    var isShort: Bool { quantity < 0 }

    /// Cost basis in the stock's own currency, signed and leverage-adjusted.
    /// Negative for shorts. Multiply by an FX rate for the preferred currency.
    var costBasisLocal: Double {
        avgPrice * quantity * effectiveLeverage
    }

    func pnl(currentPrice: Double) -> Double {
        (currentPrice - avgPrice) * quantity * effectiveLeverage
    }

    func dailyPnl(priceChange: Double) -> Double {
        priceChange * quantity * effectiveLeverage
    }

    func pnlPercent(currentPrice: Double) -> Double {
        guard avgPrice > 0 else { return 0 }
        // Exposure-relative return: a short gains when the price falls, so flip
        // the sign for negative quantities. Leverage scales P&L and exposure
        // equally, so it cancels out of the per-position percentage.
        let direction: Double = quantity < 0 ? -1 : 1
        return ((currentPrice - avgPrice) / avgPrice) * 100 * direction
    }

    func marketValue(currentPrice: Double) -> Double {
        currentPrice * quantity * effectiveLeverage
    }
}
