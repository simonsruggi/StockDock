import Foundation

extension StorageService {
    func addToWatchlist(_ symbol: String) {
        guard !watchlist.contains(symbol) else { return }
        watchlist.append(symbol)
    }

    func removeFromWatchlist(_ symbol: String) {
        watchlist.removeAll { $0 == symbol }
    }

    func moveWatchlistItem(from source: IndexSet, to destination: Int) {
        watchlist.move(fromOffsets: source, toOffset: destination)
    }

    /// Nudges a symbol one place up (`-1`) or down (`+1`) in the manual order.
    /// Returns false at the ends of the list, so callers can leave the UI alone.
    @discardableResult
    func moveWatchlistItem(_ symbol: String, by delta: Int) -> Bool {
        guard let i = watchlist.firstIndex(of: symbol) else { return false }
        let j = i + delta
        guard j >= 0, j < watchlist.count else { return false }
        watchlist.swapAt(i, j)
        return true
    }

    func addPortfolio(name: String) {
        portfolios.append(Portfolio(name: name))
    }

    func renamePortfolio(id: UUID, name: String) {
        guard let index = portfolios.firstIndex(where: { $0.id == id }) else { return }
        portfolios[index].name = name
    }

    /// Issue #14: the portfolios that make up every *combined* figure — the menu
    /// bar, "All Portfolios", the window's footer total.
    ///
    /// This is deliberately the single place the filter lives. The aggregation
    /// used to be open-coded in five files, and the menu bar disagreeing with the
    /// window about the total is exactly the bug that split would produce.
    var countedPortfolios: [Portfolio] {
        portfolios.filter { !$0.isExcludedFromTotal }
    }

    /// Includes/excludes a portfolio from the combined total.
    func setExcludedFromTotal(_ excluded: Bool, id: UUID) {
        guard let index = portfolios.firstIndex(where: { $0.id == id }) else { return }
        portfolios[index].excludedFromTotal = excluded ? true : nil
    }

    func deletePortfolio(at offsets: IndexSet) {
        let removedIds = offsets.map { portfolios[$0].id.uuidString }
        portfolios.remove(atOffsets: offsets)
        removedIds.forEach {
            portfolioNotifications[$0] = nil
            portfolioSnapshots[$0] = nil
        }
    }

    func deletePortfolio(id: UUID) {
        portfolios.removeAll { $0.id == id }
        portfolioNotifications[id.uuidString] = nil
        portfolioSnapshots[id.uuidString] = nil
    }

    func deleteAllPortfolios() {
        portfolios.removeAll()
        portfolioNotifications = [:]
        portfolioSnapshots = [:]
    }

    func addHolding(to portfolioId: UUID, symbol: String, quantity: Double, avgPrice: Double, purchaseDate: Date? = nil, leverage: Double? = nil) {
        guard let index = portfolios.firstIndex(where: { $0.id == portfolioId }) else { return }
        let holding = Holding(symbol: symbol, quantity: quantity, avgPrice: avgPrice, purchaseDate: purchaseDate, leverage: leverage)
        portfolios[index].holdings.append(holding)
    }

    func removeHolding(from portfolioId: UUID, holdingId: UUID) {
        guard let pIndex = portfolios.firstIndex(where: { $0.id == portfolioId }) else { return }
        portfolios[pIndex].holdings.removeAll { $0.id == holdingId }
    }

    func updateHolding(in portfolioId: UUID, holdingId: UUID, quantity: Double, avgPrice: Double, purchaseDate: Date? = nil, leverage: Double? = nil) {
        guard let pIndex = portfolios.firstIndex(where: { $0.id == portfolioId }),
              let hIndex = portfolios[pIndex].holdings.firstIndex(where: { $0.id == holdingId })
        else { return }
        let old = portfolios[pIndex].holdings[hIndex]
        // A hand-edited cost or date is no longer the broker's booking.
        if old.avgPrice != avgPrice || old.purchaseDate != purchaseDate {
            portfolios[pIndex].holdings[hIndex].costRate = nil
            portfolios[pIndex].holdings[hIndex].costRateCurrency = nil
        }
        portfolios[pIndex].holdings[hIndex].quantity = quantity
        portfolios[pIndex].holdings[hIndex].avgPrice = avgPrice
        portfolios[pIndex].holdings[hIndex].purchaseDate = purchaseDate
        portfolios[pIndex].holdings[hIndex].leverage = leverage
    }
}
