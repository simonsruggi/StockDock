import AppKit
import SwiftUI

/// Home tab: a compact finance news feed related to the user's tracked symbols
/// (or general market news when nothing is tracked). Tapping a story opens it
/// in the default browser.
struct HomeView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(stockService.news) { article in
                            NewsRow(article: article)
                            Divider().padding(.leading, 74)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task {
            await stockService.refreshNews(storageService: storageService)
        }
    }
}

/// A single news story row: thumbnail, headline, publisher · relative time, related tickers.
private struct NewsRow: View {
    let article: NewsArticle
    @Environment(\.locale) private var locale
    @State private var hovering = false

    private var relativeTime: String {
        guard article.publishTime > 0 else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .abbreviated
        return f.localizedString(for: article.publishedAt, relativeTo: Date())
    }

    var body: some View {
        Button {
            if let url = article.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 3) {
                    Text(article.title)
                        .font(.inter(12, weight: .semibold, relativeTo: .body))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        if !article.publisher.isEmpty {
                            Text(article.publisher)
                                .font(.inter(9, relativeTo: .caption2))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        if !relativeTime.isEmpty {
                            Text("·").font(.inter(9, relativeTo: .caption2)).foregroundColor(.secondary)
                            Text(relativeTime)
                                .font(.inter(9, relativeTo: .caption2))
                                .foregroundColor(.secondary)
                        }
                    }
                    if !article.relatedTickers.isEmpty {
                        Text(article.relatedTickers.prefix(4).joined(separator: " · "))
                            .font(.inter(8, weight: .medium, relativeTo: .caption2))
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(hovering ? Color.secondary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(article.title)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb = article.thumbnailURL, let url = URL(string: thumb) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    Rectangle().fill(Color.secondary.opacity(0.08))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.08))
            .frame(width: 52, height: 52)
            .overlay(
                Image(systemName: "newspaper")
                    .font(.inter(16, relativeTo: .body))
                    .foregroundColor(.secondary)
            )
    }
}
