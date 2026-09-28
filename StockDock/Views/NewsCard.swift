import SwiftUI
import AppKit

struct NewsCard: View {
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
