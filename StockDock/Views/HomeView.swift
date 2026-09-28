import AppKit
import SwiftUI

/// Home tab: a compact finance news feed related to the user's tracked symbols
/// (or general market news when nothing is tracked). Tapping a story opens it
/// in the default browser.
struct HomeView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @State private var query = ""

    /// Filters by headline, tickers (source + related) and publisher.
    private var filteredNews: [NewsArticle] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return stockService.news }
        return stockService.news.filter { a in
            a.title.lowercased().contains(q)
            || a.publisher.lowercased().contains(q)
            || (a.sourceSymbol?.lowercased().contains(q) ?? false)
            || a.relatedTickers.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        Group {
            if stockService.news.isEmpty {
                if stockService.isLoadingNews {
                    VStack(spacing: 10) {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                        Text("Loading news…")
                            .font(.inter(11, relativeTo: .caption))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "newspaper")
                            .font(.inter(32, relativeTo: .largeTitle))
                            .foregroundColor(.secondary)
                        Text("No news available")
                            .font(.inter(12, relativeTo: .body))
                            .foregroundColor(.secondary)
                        Button("Refresh") {
                            Task { await stockService.refreshNews(storageService: storageService, force: true) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    searchField
                    Divider()
                    let news = filteredNews
                    if news.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.inter(24, relativeTo: .title)).foregroundColor(.secondary)
                            Text("No stories match")
                                .font(.inter(11, relativeTo: .caption)).foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(news) { article in
                                    NewsRow(article: article)
                                    Divider().padding(.leading, 74)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .task {
            await stockService.refreshNews(storageService: storageService)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary).font(.inter(10, relativeTo: .caption))
            TextField("Search news or ticker", text: $query)
                .textFieldStyle(.plain)
                .font(.inter(11, relativeTo: .caption))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary).font(.inter(10, relativeTo: .caption))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
