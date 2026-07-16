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

// MARK: - Featured

/// The lead story: a wide two-pane card — image fused into the text pane via a
/// soft gradient seam, gold FEATURED label, Craft-style image zoom on hover.
private struct FeaturedNewsCard: View {
    let article: NewsArticle
    @Environment(\.locale) private var locale
    @State private var hovered = false

    private var relativeTime: String {
        guard article.publishTime > 0 else { return "" }
        let f = RelativeDateTimeFormatter(); f.locale = locale; f.unitsStyle = .abbreviated
        return f.localizedString(for: article.publishedAt, relativeTo: Date())
    }
    private var referenceTicker: String? { article.sourceSymbol ?? article.relatedTickers.first }

    var body: some View {
        Button {
            if let url = article.url { NSWorkspace.shared.open(url) }
        } label: {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    thumbnail
                        .frame(width: geo.size.width * 0.44)
                        .frame(maxHeight: .infinity)
                        .clipped()
                        .overlay(alignment: .trailing) {
                            LinearGradient(colors: [.clear, DS.card],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: 40)
                        }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text("FEATURED")
                                .font(.inter(9.5, weight: .bold, relativeTo: .caption2))
                                .tracking(1.2)
                                .foregroundStyle(DS.gold)
                            if !relativeTime.isEmpty {
                                Text("· \(relativeTime)").font(DS.micro).foregroundStyle(DS.inkTertiary)
                            }
                        }
                        Text(article.title)
                            .font(.inter(22, weight: .semibold, relativeTo: .title2))
                            .foregroundStyle(DS.ink)
                            .lineSpacing(2)
                            .lineLimit(3).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            if let ref = referenceTicker { TickerChipWide(text: ref, emphasized: true) }
                            ForEach(article.relatedTickers.filter { $0 != referenceTicker }.prefix(3), id: \.self) {
                                TickerChipWide(text: $0, emphasized: false)
                            }
                            Spacer()
                            if !article.publisher.isEmpty {
                                Text(article.publisher).font(DS.micro).foregroundStyle(DS.inkTertiary)
                            }
                        }
                    }
                    .padding(DS.pad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .premiumCard(elevated: hovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(article.title)
    }

    @ViewBuilder private var thumbnail: some View {
        if let thumb = article.thumbnailURL, let url = URL(string: thumb) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                        .scaleEffect(hovered ? 1.03 : 1)
                        .animation(.easeOut(duration: 0.3), value: hovered)
                case .failure: NewsPlaceholder(publisher: article.publisher)
                default: Rectangle().fill(DS.cardAlt)
                }
            }
        } else {
            NewsPlaceholder(publisher: article.publisher)
        }
    }
}

// MARK: - Grid card

private struct NewsCard: View {
    let article: NewsArticle
    @Environment(\.locale) private var locale
    @State private var hovered = false

    private var relativeTime: String {
        guard article.publishTime > 0 else { return "" }
        let f = RelativeDateTimeFormatter(); f.locale = locale; f.unitsStyle = .abbreviated
        return f.localizedString(for: article.publishedAt, relativeTo: Date())
    }
    private var referenceTicker: String? { article.sourceSymbol ?? article.relatedTickers.first }
    private var otherTickers: [String] { Array(article.relatedTickers.filter { $0 != referenceTicker }.prefix(2)) }

    var body: some View {
        Button {
            if let url = article.url { NSWorkspace.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title)
                        .font(.inter(13, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(DS.ink)
                        .lineSpacing(1.5)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if let ref = referenceTicker {
                            TickerChipWide(text: ref, emphasized: true)
                            ForEach(otherTickers, id: \.self) { TickerChipWide(text: $0, emphasized: false) }
                        }
                        Spacer()
                        if !article.publisher.isEmpty {
                            Text(article.publisher).font(DS.micro).foregroundStyle(DS.inkTertiary).lineLimit(1)
                        }
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 232)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .premiumCard(elevated: hovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(article.title)
    }

    @ViewBuilder private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let thumb = article.thumbnailURL, let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                                .scaleEffect(hovered ? 1.02 : 1)
                                .animation(.easeOut(duration: 0.3), value: hovered)
                        case .failure: NewsPlaceholder(publisher: article.publisher)
                        default: Rectangle().fill(DS.cardAlt)
                        }
                    }
                } else { NewsPlaceholder(publisher: article.publisher) }
            }
            .frame(height: 120).frame(maxWidth: .infinity).clipped()

            // Scrim keeps the timestamp legible over any image.
            LinearGradient(colors: [.clear, .black.opacity(0.25)],
                           startPoint: .center, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false)

            if !relativeTime.isEmpty {
                Text(relativeTime)
                    .font(DS.micro).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .padding(8)
            }
        }
        .frame(height: 120)
    }
}

/// A named placeholder reads intentional; a lone glyph reads broken.
private struct NewsPlaceholder: View {
    let publisher: String
    var body: some View {
        Rectangle().fill(DS.cardAlt)
            .overlay(
                VStack(spacing: 5) {
                    Image(systemName: "newspaper").font(.system(size: 20)).foregroundStyle(DS.inkTertiary)
                    if !publisher.isEmpty {
                        Text(publisher).font(DS.micro).foregroundStyle(DS.inkTertiary)
                    }
                }
            )
    }
}

private struct TickerChipWide: View {
    let text: String; let emphasized: Bool
    var body: some View {
        Text(text).font(DS.micro)
            .foregroundStyle(emphasized ? Color.white : DS.brand)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(emphasized ? DS.brand : DS.brand.opacity(0.10)))
    }
}
