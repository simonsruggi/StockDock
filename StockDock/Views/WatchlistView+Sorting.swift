import SwiftUI

extension WatchlistView {
    var sortedSymbols: [String] {
        guard sortColumn != .manual else { return storageService.watchlist }
        return storageService.watchlist.sorted { a, b in
            let qa = stockService.quotes[a]
            let qb = stockService.quotes[b]
            let result: Bool
            switch sortColumn {
            case .symbol:
                result = a.localizedCompare(b) == .orderedAscending
            case .price:
                let pa = qa?.price ?? 0
                let pb = qb?.price ?? 0
                result = pa < pb
            case .change:
                let ca = qa?.changePercent ?? 0
                let cb = qb?.changePercent ?? 0
                result = ca < cb
            case .manual:
                result = false  // unreachable: the guard above returns the stored order
            }
            return sortAscending ? result : !result
        }
    }

    var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return sortedSymbols }
        let query = searchText.lowercased()
        return sortedSymbols.filter { symbol in
            symbol.lowercased().contains(query) ||
            (stockService.quotes[symbol]?.name.lowercased().contains(query) ?? false) ||
            (storageService.isinMap[symbol]?.lowercased().contains(query) ?? false)
        }
    }
}
