import Foundation

/// Forgiving text match: case and accent insensitive, every word of the query
/// must hit one of the fields, and better hits (exact, prefix, word start) rank higher.
enum SearchMatcher {
    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Score for `query` against `fields` (first fields weigh more); nil when a word misses.
    static func score(_ query: String, fields: [String]) -> Int? {
        let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let haystacks = fields.map(normalize)
        var total = 0
        for token in tokens {
            var best = 0
            for (index, field) in haystacks.enumerated() where !field.isEmpty {
                let weight = index == 0 ? 10 : (index == 1 ? 8 : 6)
                best = max(best, tokenScore(token, in: field) * weight / 10)
            }
            guard best > 0 else { return nil }
            total += best
        }
        return total / tokens.count
    }

    private static func tokenScore(_ token: String, in field: String) -> Int {
        if field == token { return 100 }
        if field.hasPrefix(token) { return 85 }
        let words = field.split { !$0.isLetter && !$0.isNumber && $0 != "%" && $0 != "/" }
        if words.contains(where: { $0.hasPrefix(token) }) { return 70 }
        // One or two letters inside a word ("mu" in "Amundi") is noise, not intent.
        guard token.count >= 3 else { return 0 }
        if field.contains(token) { return 50 }
        // Letters in order with gaps only inside a single word that starts the same way.
        return words.contains { $0.first == token.first && $0.count <= token.count * 3 && isSubsequence(token, of: String($0)) } ? 20 : 0
    }

    /// "pfl" in "portfolio": the letters in order, gaps allowed — tolerates typos of omission.
    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var it = haystack.makeIterator()
        return needle.allSatisfy { ch in
            while let next = it.next() { if next == ch { return true } }
            return false
        }
    }
}
