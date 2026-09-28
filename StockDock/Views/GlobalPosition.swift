import Foundation

/// Global average buy price: one row per symbol, aggregated across the
/// portfolios counted in the total.
struct GlobalPosition: Identifiable {
    let id: String            // symbol
    let avgPrice: Double      // weighted avg buy price, in the price currency
    let currentPrice: Double  // latest quote price, same currency as avgPrice
    let priceSymbol: String
    let pct: Double           // price return vs. avg (position-direction aware)
    let value: Double         // market value (preferred currency), for sorting
    var symbol: String { id }

    /// Per-symbol weighted-average buy price across ALL portfolios, with the
    /// current price return vs. that average. Sorted by market value.
    @MainActor
    static func all(storage: StorageService, stocks: StockService) -> [GlobalPosition] {
        var qty: [String: Double] = [:]
        var qtyPrice: [String: Double] = [:]
        for portfolio in storage.countedPortfolios {
            for h in portfolio.holdings {
                qty[h.symbol, default: 0] += h.quantity
                qtyPrice[h.symbol, default: 0] += h.quantity * h.avgPrice
            }
        }
        return qty.compactMap { symbol, q -> GlobalPosition? in
            guard abs(q) >= 1e-9, let quote = stocks.quotes[symbol] else { return nil }
            let avg = qtyPrice[symbol, default: 0] / q
            let price = quote.displayPrice(extendedHours: storage.showExtendedHours)
            let rawPct = abs(avg) >= 1e-6 ? (price / avg - 1) * 100 : 0
            // A short position gains when the price falls, so flip the sign.
            let pct = q >= 0 ? rawPct : -rawPct
            let priced = stocks.priceDisplay(for: quote.currency)
            let priceSymbol = StorageService.currencySymbol(for: priced.currency)
            let value = abs(price * q) * stocks.rate(from: quote.currency)
            return GlobalPosition(id: symbol, avgPrice: avg * priced.rate, currentPrice: price * priced.rate,
                                  priceSymbol: priceSymbol, pct: pct, value: value)
        }
        .sorted { $0.value > $1.value }
    }
}
