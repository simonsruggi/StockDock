import SwiftUI

extension PriceChartCard {
    func hoverLabel(_ date: Date) -> String {
        chartRange.isIntraday ? date.formatted(.dateTime.hour().minute())
                              : date.formatted(date: .abbreviated, time: .omitted)
    }

    /// X-axis tick label, formatted for the selected period.
    func xAxisLabel(_ date: Date) -> String {
        switch chartRange {
        case .day: return date.formatted(.dateTime.hour().minute())
        case .week: return date.formatted(.dateTime.weekday(.abbreviated))
        case .month, .threeMonths, .sixMonths, .ytd: return date.formatted(.dateTime.day().month(.abbreviated))
        case .year, .fiveYears, .all: return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }
    var history: [PricePoint] {
        if chartRange.isIntraday {
            return stockService.intradayHistory[symbol] ?? []
        }
        if chartRange == .all {
            return stockService.priceHistoryMax[symbol] ?? []
        }
        if chartRange == .fiveYears {
            return stockService.priceHistory5y[symbol] ?? []
        }
        guard let all = stockService.priceHistory[symbol] else { return [] }
        guard let cutoff = chartRange.cutoff else { return all }
        let inRange = all.filter { $0.date >= cutoff }
        // YTD is measured from last year's final close, so keep it as the first point.
        if chartRange == .ytd, let base = all.last(where: { $0.date < cutoff }) {
            return [base] + inRange
        }
        return inRange
    }

    var isLoadingCurrent: Bool {
        switch chartRange {
        case .day: return stockService.intradayHistory[symbol] == nil
        case .all: return stockService.priceHistoryMax[symbol] == nil
        case .fiveYears: return stockService.priceHistory5y[symbol] == nil
        default: return stockService.priceHistory[symbol] == nil
        }
    }
    var chartDomain: ClosedRange<Double> {
        let closes = history.map(\.close)
        guard let min = closes.min(), let max = closes.max(), max > min else { return 0...1 }
        let pad = (max - min) * 0.12
        return (min - pad)...(max + pad)
    }
}
