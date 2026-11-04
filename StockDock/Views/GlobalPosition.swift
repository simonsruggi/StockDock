import Foundation

/// Global average buy price: one row per symbol, aggregated across the
/// portfolios counted in the total.
struct GlobalPosition: Identifiable {
    let id: String            // symbol
    let avgPrice: Double      // weighted avg buy price, in the price currency
    let currentPrice: Double  // latest quote price, same currency as avgPrice
    let priceSymbol: String
    let pct: Double           // P&L % in the preferred currency, after tax
    let value: Double         // market value (preferred currency), for sorting
    var symbol: String { id }

    /// Per-symbol weighted-average buy price across ALL portfolios, with the
    /// current price return vs. that average. Sorted by market value.
    @MainActor
    static func all(storage: StorageService, stocks: StockService) -> [GlobalPosition] {
        var qty: [String: Double] = [:]
        var qtyPrice: [String: Double] = [:]
        var marketValue: [String: Double] = [:]
        var cost: [String: Double] = [:]
        for portfolio in storage.countedPortfolios {
            for h in portfolio.holdings {
                qty[h.symbol, default: 0] += h.quantity
                qtyPrice[h.symbol, default: 0] += h.quantity * h.avgPrice
                guard let quote = stocks.quotes[h.symbol] else { continue }
                let price = HyperliquidService.shared.livePrice(for: quote, extendedHours: storage.showExtendedHours)
                marketValue[h.symbol, default: 0] += h.marketValue(currentPrice: price) * stocks.rate(from: quote.currency)
                cost[h.symbol, default: 0] += h.costBasisLocal * stocks.costRate(for: h, currency: quote.currency)
            }
        }
        return qty.compactMap { symbol, q -> GlobalPosition? in
            guard abs(q) >= 1e-9, let quote = stocks.quotes[symbol] else { return nil }
            let avg = qtyPrice[symbol, default: 0] / q
            let price = HyperliquidService.shared.livePrice(for: quote, extendedHours: storage.showExtendedHours)
            // Same P&L % as the desktop Positions table: value vs. cost in the
            // preferred currency (purchase-date FX), after tax.
            let pct = storage.afterTax(PortfolioValuation.pnlPercent(value: marketValue[symbol, default: 0],
                                                                     cost: cost[symbol, default: 0]))
            let priced = stocks.priceDisplay(for: quote.currency)
            let priceSymbol = StorageService.currencySymbol(for: priced.currency)
            let value = abs(price * q) * stocks.rate(from: quote.currency)
            return GlobalPosition(id: symbol, avgPrice: avg * priced.rate, currentPrice: price * priced.rate,
                                  priceSymbol: priceSymbol, pct: pct, value: value)
        }
        .sorted { $0.value > $1.value }
    }
}
