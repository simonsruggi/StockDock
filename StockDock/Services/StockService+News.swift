import Foundation

extension StockService {
    func search(query: String) async -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://query2.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=10&newsCount=0") else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
            return response.quotes
        } catch {
            return []
        }
    }

    // MARK: - Finance News (Home tab)

    /// Refresh the Home news feed. Pulls stories related to the user's tracked
    /// symbols (or general market news when nothing is tracked), from the same
    /// Yahoo search endpoint used for quote lookup — no API key required.
    /// Throttled to at most once every 5 minutes unless `force` is set.
    func refreshNews(storageService: StorageService, force: Bool = false) async {
        if !force, !news.isEmpty, let last = lastNewsFetch,
           Date().timeIntervalSince(last) < 300 {
            return
        }
        isLoadingNews = true
        defer { isLoadingNews = false }

        let symbols = Self.collectSymbols(storageService: storageService).sorted()
        // Each query is (search term, reference ticker). For tracked symbols the
        // reference ticker is the symbol itself; the general-market fallback has none.
        let queries: [(term: String, symbol: String?)] = symbols.isEmpty
            ? [("stock market", nil)]
            : symbols.prefix(6).map { ($0, $0) }

        var seen = Set<String>()
        var collected: [NewsArticle] = []
        await withTaskGroup(of: [NewsArticle].self) { group in
            for query in queries {
                group.addTask { [weak self] in
                    await self?.fetchNewsChunk(query: query.term, sourceSymbol: query.symbol) ?? []
                }
            }
            for await chunk in group {
                for article in chunk where !article.link.isEmpty && seen.insert(article.id).inserted {
                    collected.append(article)
                }
            }
        }
        collected.sort { $0.publishTime > $1.publishTime }
        news = Array(collected.prefix(40))
        lastNewsFetch = Date()
    }

    private func fetchNewsChunk(query: String, sourceSymbol: String?) async -> [NewsArticle] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=0&newsCount=10") else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            let articles = try JSONDecoder().decode(YahooNewsResponse.self, from: data).news ?? []
            guard let sourceSymbol else { return articles }
            return articles.map { var a = $0; a.sourceSymbol = sourceSymbol; return a }
        } catch {
            return []
        }
    }
}
