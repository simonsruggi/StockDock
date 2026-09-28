import Foundation

extension PortfolioValuation {
    /// Valuation inputs for the holdings that currently have a quote: price as
    /// displayed (extended-hours aware), today's FX for the value and the
    /// purchase-day FX for the cost. Holdings without a quote are skipped.
    @MainActor
    static func inputs(for holdings: [Holding], stockService: StockService, storageService: StorageService) -> [Input] {
        holdings.compactMap { holding in
            guard let quote = stockService.quotes[holding.symbol] else { return nil }
            return Input(
                holding: holding,
                price: quote.displayPrice(extendedHours: storageService.showExtendedHours),
                rate: stockService.rate(from: quote.currency),
                costRate: stockService.rate(from: quote.currency, for: holding.purchaseDate)
            )
        }
    }
}
