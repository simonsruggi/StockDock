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
        case .month: return date.formatted(.dateTime.day().month(.abbreviated))
        case .year, .all: return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        }
    }
    var history: [PricePoint] {
        if chartRange.isIntraday {
            return stockService.intradayHistory[symbol] ?? []
        }
        if chartRange == .all {
            return stockService.priceHistoryMax[symbol] ?? []
        }
        guard let all = stockService.priceHistory[symbol] else { return [] }
        guard let days = chartRange.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        else { return all }
        return all.filter { $0.date >= cutoff }
    }

    var isLoadingCurrent: Bool {
        switch chartRange {
        case .day: return stockService.intradayHistory[symbol] == nil
        case .all: return stockService.priceHistoryMax[symbol] == nil
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
