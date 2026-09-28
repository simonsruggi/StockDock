import SwiftUI

/// A holding priced in the preferred currency, with the derived figures the
/// overview needs.
struct ValuedHolding: Identifiable {
    let id: UUID
    let portfolioId: UUID
    let holding: Holding
    let quote: StockQuote
    let value: Double
    let cost: Double
    let dayChangePercent: Double
    let type: String
    /// #24: `value` and `cost` are in the preferred currency, but a per-share
    /// price is not — it follows the "stock price currency" setting, exactly as
    /// the watchlist and the compact list do. These two carry that conversion so
    /// the Last/Change columns can never print a native figure under the
    /// portfolio currency's symbol.
    let priceRate: Double
    let priceCurrency: String

    var symbol: String { holding.symbol }
    var name: String { quote.name.isEmpty ? holding.symbol : quote.name }
    var pnl: Double { value - cost }
    var pnlPercent: Double { abs(cost) >= 0.01 ? (pnl / abs(cost)) * 100 : 0 }
}
