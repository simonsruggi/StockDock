import Foundation

extension StockService {
    /// Loads (or refreshes after ~6h) the daily closes of `from`→`to`.
    func ensureFXHistory(from: String, to: String) async {
        guard from != to else { return }
        let pair = from + to
        if let at = fxHistoryAt[pair], Date().timeIntervalSince(at) < 21600, fxHistory[pair]?.isEmpty == false { return }
        guard let points = await chartPoints(for: "\(pair)=X", query: "interval=1d&range=5y"), !points.isEmpty else { return }
        fxHistory[pair] = points
        fxHistoryAt[pair] = Date()
    }

    /// Daily rates from `currency` to the preferred currency; empty when they
    /// are the same or the series hasn't loaded (callers fall back to today's rate).
    func rateHistory(from currency: String) -> [PricePoint] {
        let preferred = StorageService.shared.preferredCurrency
        guard currency != preferred else { return [] }
        return fxHistory[currency + preferred] ?? []
    }
}
