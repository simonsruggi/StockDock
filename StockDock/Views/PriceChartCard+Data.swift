import SwiftUI

extension PriceChartCard {
    /// The series drawn for the selected range. Read once per render in `body`
    /// and passed down, not re-read by every mark.
    var history: [PricePoint] {
        switch chartRange {
        case .day:
            return HyperliquidService.shared.chartHistory(stockService.intradayHistory[symbol] ?? [], for: quote, span: .day)
        case .fiveYears: return stockService.priceHistory5y[symbol] ?? []
        case .all: return stockService.priceHistoryMax[symbol] ?? []
        default:
            guard let daily = stockService.priceHistory[symbol] else { return [] }
            return chartRange.slice(daily, date: \.date)
        }
    }

    /// Percent change from the range's first close to the live price; nil on
    /// 24H, where the "today" pill already says it.
    func periodChange(_ points: [PricePoint], livePrice: Double) -> Double? {
        guard chartRange != .day, points.count >= 2, let first = points.first?.close, first > 0 else { return nil }
        return (livePrice - first) / first * 100
    }

    /// True while the range's series is still on its way. A failed request is
    /// not "loading": the card says there is no history instead of spinning forever.
    var isLoadingCurrent: Bool {
        let kind: StockService.HistoryKind
        let loaded: Bool
        switch chartRange {
        case .day: kind = .intraday; loaded = stockService.intradayHistory[symbol] != nil
        case .fiveYears: kind = .fiveYears; loaded = stockService.priceHistory5y[symbol] != nil
        case .all: kind = .max; loaded = stockService.priceHistoryMax[symbol] != nil
        default: kind = .daily; loaded = stockService.priceHistory[symbol] != nil
        }
        return !loaded && !stockService.historyFailed(kind, symbol)
    }
}
