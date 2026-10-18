import Foundation

/// Maps Yahoo symbols to Hyperliquid perpetuals on the trade.xyz market
/// (`xyz:` prefix), which trade 24/7.
enum HyperliquidSymbols {
    static let dex = "xyz"

    /// Futures, indices and FX, whose Yahoo symbol differs from the coin name.
    static let explicit: [String: String] = [
        "GC=F": "xyz:GOLD", "SI=F": "xyz:SILVER", "PL=F": "xyz:PLATINUM", "PA=F": "xyz:PALLADIUM",
        "HG=F": "xyz:COPPER", "ALI=F": "xyz:ALUMINIUM",
        "CL=F": "xyz:CL", "BZ=F": "xyz:BRENTOIL", "NG=F": "xyz:NATGAS", "HO=F": "xyz:HO",
        "^GSPC": "xyz:SP500", "^NDX": "xyz:XYZ100", "^N225": "xyz:JP225",
        "^BVSP": "xyz:IBOV", "^KS200": "xyz:KR200",
        "EURUSD=X": "xyz:EUR", "GBPUSD=X": "xyz:GBP", "JPY=X": "xyz:JPY",
    ]

    /// Coins that aren't the stock with the same ticker (GOLD is not Barrick,
    /// CL is not Colgate): they are reachable only through `explicit`.
    private static let notEquities: Set<String> = [
        "GOLD", "SILVER", "PLATINUM", "PALLADIUM", "COPPER", "ALUMINIUM", "URANIUM",
        "CL", "BRENTOIL", "NATGAS", "HO", "TTF", "CORN", "WHEAT",
        "SP500", "XYZ100", "JP225", "IBOV", "KR200", "NIFTY", "VIX", "VOL", "DXY",
        "EUR", "GBP", "JPY", "KRW", "H100", "DRAM",
    ]

    /// Candidate coin for a Yahoo symbol, or nil when there is none. Plain
    /// tickers (no suffix) map to the coin of the same name.
    static func coin(for symbol: String) -> String? {
        if let c = explicit[symbol] { return c }
        let s = symbol.uppercased()
        guard !s.isEmpty, s.allSatisfy({ $0.isLetter }), !notEquities.contains(s) else { return nil }
        return "\(dex):\(s)"
    }

    /// Direct ticker matches only count for USD quotes: a coin is always in USD.
    static func accepts(symbol: String, currency: String) -> Bool {
        explicit[symbol] != nil || currency == "USD"
    }

    /// Guard against a coin that shares the ticker but tracks something else:
    /// the perp must sit within 25% of the last regular close.
    static func isPlausible(_ price: Double, reference: Double) -> Bool {
        guard price > 0, reference > 0 else { return false }
        return abs(price / reference - 1) < 0.25
    }
}
