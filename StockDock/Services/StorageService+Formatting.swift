import Foundation

extension StorageService {
    /// Issue #10: how many decimals to show for a *market price*. Two decimals is
    /// right for normal stocks, but forex pairs (e.g. CADUSD=X = 0.7119) and any
    /// sub-dollar instrument (penny stocks, low-priced crypto) lose meaningful
    /// precision at 2 decimals, so they get 4. Big forex crosses (e.g. USDJPY ≈ 149)
    /// stay at 2 to avoid pointless trailing zeros.
    nonisolated static func priceDecimals(symbol: String, price: Double) -> Int {
        let isForex = symbol.uppercased().hasSuffix("=X")
        let magnitude = abs(price)
        if isForex { return magnitude >= 50 ? 2 : 4 }
        if magnitude > 0 && magnitude < 1 { return 4 }
        return 2
    }

    /// Formats a share count: whole numbers stay whole ("12"), fractional shares
    /// keep two decimals ("12.50"). Negative = a short position, kept signed.
    nonisolated static func formatQuantity(_ qty: Double) -> String {
        qty == qty.rounded(.down) ? String(format: "%.0f", qty) : String(format: "%.2f", qty)
    }

    /// Formats a plain number with a thousands grouping separator and locale-aware
    /// decimal separator, e.g. "1,234.56" (en) / "1.234,56" (it). Falls back to a
    /// non-grouped representation if the formatter ever fails.
    nonisolated static func formatNumber(_ value: Double, decimals: Int, truncateZeros: Bool = false, locale: Locale = .autoupdatingCurrent) -> String {
        // Grouping is inserted manually (every 3 digits from the right) so every value
        // > 1,000 is separated regardless of the locale's CLDR rule (e.g. it/es only group
        // from 10,000 by default), and without needing macOS 15's `minimumGroupingDigits`.
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal

        let groupSep = formatter.groupingSeparator ?? ","
        let decSep = formatter.decimalSeparator ?? "."

        // Reuse the formatter to produce the raw digits: en_US + no grouping yields a
        // plain "1234.56" we regroup below, and minimumFractionDigits = 0 lets us drop
        // trailing zeros when `truncateZeros` is set — something `%f` can't do.
        formatter.locale = Locale(identifier: "en_US")
        formatter.groupingSeparator = ""
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = truncateZeros ? 0 : decimals

        // Falls back to a non-grouped %f representation if the formatter ever fails.
        let rounded = formatter.string(from: NSNumber(value: abs(value)))
            ?? String(format: "%.\(decimals)f", abs(value))
        let parts = rounded.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intDigits = String(parts[0])
        let fracDigits = parts.count > 1 ? String(parts[1]) : ""

        var grouped = ""
        var count = 0
        for ch in intDigits.reversed() {
            if count > 0 && count % 3 == 0 { grouped.append(contentsOf: groupSep.reversed()) }
            grouped.append(ch)
            count += 1
        }
        var result = String(grouped.reversed())
        if !fracDigits.isEmpty { result += decSep + fracDigits }
        return (value < 0 ? "-" : "") + result
    }

    /// Formats an amount with the currency symbol *before* the figure, e.g.
    /// "€1,234.56", "+€820.00", "-€540.00". The sign (when shown) precedes the symbol.
    nonisolated static func formatAmount(_ value: Double, symbol: String, decimals: Int = 2, signed: Bool = false, truncateZeros: Bool = false,
                             locale: Locale = .autoupdatingCurrent) -> String {
        let sign = signed ? (value >= 0 ? "+" : "-") : (value < 0 ? "-" : "")
        let magnitude = formatNumber(abs(value), decimals: decimals, truncateZeros: truncateZeros, locale: locale)
        return "\(sign)\(symbol)\(magnitude)"
    }

    /// Issue #8.3: true when a symbol is a market index, which has no associated
    /// currency (so no currency symbol should prefix its value). Uses the resolved
    /// Yahoo type when known, falling back to the "^" convention (e.g. ^GSPC).
    nonisolated static func isIndex(symbol: String, type: String?) -> Bool {
        if let t = type, !t.isEmpty { return t.uppercased() == "INDEX" }
        return symbol.hasPrefix("^")
    }

    /// Issue #8.1: orders watchlist symbols for the menu bar ticker cycle.
    /// "type" groups by asset class (stocks → ETFs → indices → futures → …),
    /// keeping the original relative order within each group (stable). Symbols with
    /// an unknown type sort last. "alpha" sorts alphabetically. "manual" (default)
    /// preserves the as-added order.
    nonisolated static func tickerOrder(_ symbols: [String], mode: String, types: [String: String]) -> [String] {
        switch mode {
        case "alpha":
            return symbols.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case "type":
            func rank(_ symbol: String) -> Int {
                switch (types[symbol] ?? "").uppercased() {
                case "EQUITY": return 0
                case "ETF": return 1
                case "INDEX": return 2
                case "FUTURE": return 3
                case "MUTUALFUND": return 4
                case "CURRENCY": return 5
                case "CRYPTOCURRENCY": return 6
                case "": return 100 // unknown type → end
                default: return 50
                }
            }
            return symbols.enumerated()
                .sorted { a, b in
                    let ra = rank(a.element), rb = rank(b.element)
                    return ra != rb ? ra < rb : a.offset < b.offset // stable within a group
                }
                .map { $0.element }
        default:
            return symbols
        }
    }

    /// Orders rows by their pre/post-market % move (the meaningful figure during
    /// extended hours), NOT by the raw extended-hours price. Rows without an
    /// extended-hours quote (`nil` percent) always sink to the bottom, regardless
    /// of sort direction. Descending puts the biggest movers first.
    nonisolated static func sortedByExtendedPercent<Row>(
        _ rows: [Row], ascending: Bool, percent: (Row) -> Double?
    ) -> [Row] {
        rows.sorted { a, b in
            switch (percent(a), percent(b)) {
            case let (x?, y?): return ascending ? x < y : x > y
            case (_?, nil):    return true   // a has ext data, b doesn't → a first
            case (nil, _?):    return false  // b has ext data → b first
            case (nil, nil):   return false
            }
        }
    }

    static func currencySymbol(for code: String) -> String {
        switch code {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        case "CHF": return "CHF"
        case "JPY": return "¥"
        case "CAD": return "C$"
        case "AUD": return "A$"
        default: return code
        }
    }
}
