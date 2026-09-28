import SwiftUI
import AppKit

/// The lead story: a wide two-pane card — image fused into the text pane via a
/// soft gradient seam, gold FEATURED label, Craft-style image zoom on hover.
struct FeaturedNewsCard: View {
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
