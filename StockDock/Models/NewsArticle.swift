import Foundation

/// A single finance news story from Yahoo Finance's public search endpoint.
/// Decoded directly from the `news[]` items returned alongside quote search results,
/// so it needs no API key — consistent with the rest of the app.
struct NewsArticle: Identifiable, Decodable, Hashable {
    let id: String            // Yahoo "uuid"
    let title: String
    let publisher: String
    let link: String
    let publishTime: Int      // Unix seconds ("providerPublishTime"), 0 if missing
    let thumbnailURL: String?
    let relatedTickers: [String]

    var url: URL? { URL(string: link) }
    var publishedAt: Date { Date(timeIntervalSince1970: TimeInterval(publishTime)) }

    private enum CodingKeys: String, CodingKey {
        case id = "uuid"
        case title
        case publisher
        case link
        case publishTime = "providerPublishTime"
        case thumbnail
        case relatedTickers
    }
    private enum ThumbKeys: String, CodingKey { case resolutions }
    private struct Resolution: Decodable { let url: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        publisher = try c.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        publishTime = try c.decodeIfPresent(Int.self, forKey: .publishTime) ?? 0
        relatedTickers = try c.decodeIfPresent([String].self, forKey: .relatedTickers) ?? []
        // thumbnail.resolutions[] — prefer the last (smallest) resolution for a compact list.
        if let thumbC = try? c.nestedContainer(keyedBy: ThumbKeys.self, forKey: .thumbnail),
           let resolutions = try? thumbC.decode([Resolution].self, forKey: .resolutions) {
            thumbnailURL = resolutions.last?.url ?? resolutions.first?.url
        } else {
            thumbnailURL = nil
        }
    }

    init(id: String, title: String, publisher: String, link: String,
         publishTime: Int, thumbnailURL: String?, relatedTickers: [String]) {
        self.id = id
        self.title = title
        self.publisher = publisher
        self.link = link
        self.publishTime = publishTime
        self.thumbnailURL = thumbnailURL
        self.relatedTickers = relatedTickers
    }
}
