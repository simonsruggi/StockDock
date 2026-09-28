import SwiftUI

extension PortfolioWindowView {
    // MARK: - Aggregation helpers (reuse the shared valuation math)

    private func valued(_ portfolios: [Portfolio]) -> [PortfolioValuation.Input] {
        portfolios.flatMap { $0.holdings }.compactMap { holding in
            guard let quote = stockService.quotes[holding.symbol] else { return nil }
            return PortfolioValuation.Input(
                holding: holding,
                price: quote.displayPrice(extendedHours: storageService.showExtendedHours),
                rate: stockService.rate(from: quote.currency),
                costRate: stockService.rate(from: quote.currency, for: holding.purchaseDate)
            )
        }
    }

    func aggregateValue(for portfolios: [Portfolio]) -> Double {
        PortfolioValuation.totals(valued(portfolios)).value
    }
    func aggregateCost(for portfolios: [Portfolio]) -> Double {
        PortfolioValuation.totals(valued(portfolios)).cost
    }
    func aggregatePnlPercent(for portfolios: [Portfolio]) -> Double {
        let t = PortfolioValuation.totals(valued(portfolios))
        return abs(t.cost) >= 0.01 ? ((t.value - t.cost) / abs(t.cost)) * 100 : 0
    }

    /// Sidebar trailing figure — nil (hidden) until at least one holding is
    /// priced, so an unpriced portfolio never shows a fake "+0.0%".
    func trailingPercent(for portfolios: [Portfolio]) -> String? {
        guard !valued(portfolios).isEmpty else { return nil }
        return String(format: "%+.1f%%", aggregatePnlPercent(for: portfolios))
    }
}
