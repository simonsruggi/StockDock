import SwiftUI

extension WatchlistWideView {
    struct WatchRow: Identifiable {
        let id: String
        let order: Int
        let symbol: String
        /// #12: user-chosen display name, "" when unset.
        let alias: String
        let name: String
        let currency: String
        let price: Double            // regular market price
        let extPrice: Double?        // pre/post-market price, if any
        let extChangePercent: Double? // pre/post-market % move vs regular close
        let extLabel: String         // "Pre" / "Post"
        let change: Double
        let changePercent: Double
        let loaded: Bool
        let quote: StockQuote?
    }

    private var rows: [WatchRow] {
        storageService.watchlist.enumerated().map { index, symbol in
            let q = stockService.quotes[symbol]
            // #24: rate and currency come from one call, so the figure and the
            // symbol agree even while the FX pair is still loading.
            let priced = q.map { stockService.priceDisplay(for: $0.currency) }
            let rate = priced?.rate ?? 1
            let ext: Double? = q.flatMap { $0.isExtendedHours ? $0.effectivePrice * rate : nil }
            return WatchRow(
                id: symbol, order: index, symbol: symbol,
                alias: storageService.alias(for: symbol),
                name: q?.name ?? "",
                currency: priced?.currency ?? "",
                price: (q?.price ?? 0) * rate,
                extPrice: ext,
                extChangePercent: ext != nil ? q?.extendedChangePercent : nil,
                extLabel: q?.marketStateLabel ?? "",
                change: (q?.change ?? 0) * rate,
                changePercent: q?.changePercent ?? 0,
                loaded: q != nil, quote: q
            )
        }
    }

    var visibleRows: [WatchRow] {
        let sorted = sortedRows()
        guard !filter.isEmpty else { return sorted }
        let f = filter.lowercased()
        return sorted.filter { $0.symbol.lowercased().contains(f) || $0.name.lowercased().contains(f) }
    }

    /// True when any watchlist quote is trading pre/post-market. Drives the row
    /// hierarchy: during extended hours the After-hrs price/% reads first and the
    /// regular price dims to context; during regular hours it's the reverse.
    var extendedSession: Bool {
        storageService.showExtendedHours &&
        storageService.watchlist.contains { stockService.quotes[$0]?.isExtendedHours == true }
    }

    private func sortedRows() -> [WatchRow] {
        let base = rows
        let asc = sortAsc
        func by<T: Comparable>(_ key: (WatchRow) -> T) -> [WatchRow] {
            base.sorted { asc ? key($0) < key($1) : key($0) > key($1) }
        }
        switch sortKey {
        case .order:         return asc ? base : base.reversed()
        case .symbol:        return by { $0.symbol }
        case .name:          return by { $0.name }
        case .changePercent: return by { $0.changePercent }
        case .extChangePercent:
            // The After-hrs column is hidden when Extended Hours is off, so its
            // sort key would be stranded — fall back to the manual order.
            guard storageService.showExtendedHours else { return asc ? base : base.reversed() }
            // Sort by the pre/post-market % move, not the raw extended price.
            // Rows without an extended-hours quote sink to the bottom either way.
            return StorageService.sortedByExtendedPercent(base, ascending: asc) { $0.extChangePercent }
        }
    }
}
