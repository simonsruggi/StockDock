import Foundation

extension NewsArticle {
    /// Free-text news filter: matches the headline, the publisher and the
    /// tickers (source + related), so you can search by name or by stock.
    static func filter(_ news: [NewsArticle], query: String) -> [NewsArticle] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return news }
        return news.filter { a in
            a.title.lowercased().contains(q)
            || a.publisher.lowercased().contains(q)
            || (a.sourceSymbol?.lowercased().contains(q) ?? false)
            || a.relatedTickers.contains { $0.lowercased().contains(q) }
        }
    }
}
