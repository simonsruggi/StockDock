import Foundation

/// One symbol's position at the hovered moment of the portfolio chart.
struct HoverHolding: Identifiable {
    let symbol: String
    /// Per-share price in the "stock price currency" setting's currency, as in the positions list.
    let price: Double
    let priceSymbol: String
    let value: Double
    let cost: Double
    var id: String { symbol }
    var pnl: Double { value - cost }
    var pnlPercent: Double { abs(cost) >= 0.01 ? pnl / abs(cost) * 100 : 0 }
}

extension PortfolioOverviewView {
    /// Positions held at `date`, valued at each symbol's last close at or before
    /// it, from the same bars the curve is drawn with. On the live end of the
    /// curve the live prices are used, so the rows add up to the headline.
    func hoverBreakdown(at date: Date, isLive: Bool, _ d: Derived) -> [HoverHolding] {
        let history = intradaySource ?? estimatedHistory
        var bySymbol: [String: (price: Double, priceSymbol: String, value: Double, cost: Double)] = [:]
        for h in d.holdings {
            if let bought = h.holding.purchaseDate, Calendar.current.startOfDay(for: bought) > date { continue }
            let price: Double
            let value: Double
            if isLive {
                price = HyperliquidService.shared.livePrice(for: h.quote, extendedHours: storageService.showExtendedHours)
                value = h.value
            } else {
                guard let close = Self.close(at: date, in: history[h.symbol] ?? []) else { continue }
                price = close
                value = h.holding.marketValue(currentPrice: close) * stockService.rate(from: h.quote.currency)
            }
            var row = bySymbol[h.symbol]
                ?? (price * h.priceRate, StorageService.currencySymbol(for: h.priceCurrency), 0, 0)
            row.value += value
            row.cost += h.cost
            bySymbol[h.symbol] = row
        }
        return bySymbol
            .map { HoverHolding(symbol: $0.key, price: $0.value.price, priceSymbol: $0.value.priceSymbol, value: $0.value.value, cost: $0.value.cost) }
            .sorted { abs($0.value) > abs($1.value) }
    }

    /// Last close at or before `date`; the first bar when `date` precedes them all.
    static func close(at date: Date, in points: [PricePoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        var lo = 0, hi = points.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].date <= date { lo = mid + 1 } else { hi = mid }
        }
        return points[max(lo - 1, 0)].close
    }
}
