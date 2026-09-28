import SwiftUI
import AppKit

/// Desktop news view: a featured lead story anchoring a responsive grid of story
/// cards. Tapping opens the article in the default browser.
struct HomeWideView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 420), spacing: DS.gap)]

    /// Filters news by free text — matches the headline, the tickers (source +
    /// related), and the publisher — so you can search by name or by stock.
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
        PageScaffold("News", caption: newsCaption) {
            HStack(spacing: 12) {
                searchField
                RefreshButton(isLoading: stockService.isLoadingNews) {
                    Task { await stockService.refreshNews(storageService: storageService, force: true) }
                }
            }
        } content: {
            if stockService.news.isEmpty {
                emptyState
            } else {
                let news = filteredNews
                if news.isEmpty {
                    noMatchesState
                } else {
                    ScrollView {
                        VStack(spacing: DS.gap) {
                            if let featured = news.first {
                                FeaturedNewsCard(article: featured)
                            }
                            LazyVGrid(columns: columns, spacing: DS.gap) {
                                ForEach(news.dropFirst()) { article in
                                    NewsCard(article: article)
                                }
                            }
                        }
                        .pageColumn()
                        .padding(.top, 4)
                    }
                }
            }
        }
        .navigationTitle("Home")
        .task { await stockService.refreshNews(storageService: storageService) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(DS.inkTertiary)
            TextField("Search news or ticker", text: $query)
                .textFieldStyle(.plain)
                .font(DS.body)
                .focused($searchFocused)
                .frame(width: 180)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(DS.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(DS.cardAlt))
        .overlay(Capsule().strokeBorder(searchFocused ? DS.brand : .clear, lineWidth: 1.5))
        .animation(.easeOut(duration: 0.15), value: searchFocused)
        .help("Filter news by headline, ticker or publisher")
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.system(size: 34)).foregroundStyle(DS.inkTertiary)
            Text("No stories match “\(query)”").font(DS.bodyStrong).foregroundStyle(DS.inkSecondary)
            Button { query = "" } label: { Label("Clear search", systemImage: "xmark") }
                .buttonStyle(.bordered).tint(DS.brand)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newsCaption: String {
        if stockService.news.isEmpty { return "Market stories for your symbols" }
        let n = filteredNews.count
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(n) stories for your symbols"
        }
        return "\(n) of \(stockService.news.count) stories match"
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if stockService.isLoadingNews {
                DSSpinner(size: 22)
                Text("Loading news…").font(DS.caption).foregroundStyle(DS.inkSecondary)
            } else {
                Image(systemName: "newspaper").font(.system(size: 34)).foregroundStyle(DS.inkTertiary)
                Text("No news available").font(DS.bodyStrong).foregroundStyle(DS.inkSecondary)
                Button {
                    Task { await stockService.refreshNews(storageService: storageService, force: true) }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                    .tint(DS.brand)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
