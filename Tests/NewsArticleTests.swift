import XCTest
@testable import StockDock

final class NewsArticleTests: XCTestCase {

    /// A representative news item as returned by Yahoo's v1 search endpoint.
    private let sampleJSON = """
    {
      "uuid": "abc-123",
      "title": "Apple hits new high",
      "publisher": "Reuters",
      "link": "https://finance.yahoo.com/news/apple-hits-new-high.html",
      "providerPublishTime": 1719400000,
      "type": "STORY",
      "thumbnail": {
        "resolutions": [
          {"url": "https://img/original.jpg", "width": 1000, "height": 1000, "tag": "original"},
          {"url": "https://img/140.jpg", "width": 140, "height": 140, "tag": "140x140"}
        ]
      },
      "relatedTickers": ["AAPL", "MSFT"]
    }
    """.data(using: .utf8)!

    func testDecodesAllFields() throws {
        let a = try JSONDecoder().decode(NewsArticle.self, from: sampleJSON)
        XCTAssertEqual(a.id, "abc-123")
        XCTAssertEqual(a.title, "Apple hits new high")
        XCTAssertEqual(a.publisher, "Reuters")
        XCTAssertEqual(a.link, "https://finance.yahoo.com/news/apple-hits-new-high.html")
        XCTAssertEqual(a.publishTime, 1719400000)
        XCTAssertEqual(a.relatedTickers, ["AAPL", "MSFT"])
        XCTAssertEqual(a.url?.scheme, "https")
        XCTAssertNil(a.sourceSymbol, "sourceSymbol is not part of the payload; set by the fetcher")
    }

    func testPrefersSmallestThumbnailResolution() throws {
        let a = try JSONDecoder().decode(NewsArticle.self, from: sampleJSON)
        XCTAssertEqual(a.thumbnailURL, "https://img/140.jpg")
    }

    func testMissingOptionalFieldsFallBackGracefully() throws {
        let minimal = """
        {"uuid": "x1", "link": "https://example.com/a"}
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode(NewsArticle.self, from: minimal)
        XCTAssertEqual(a.id, "x1")
        XCTAssertEqual(a.title, "")
        XCTAssertEqual(a.publisher, "")
        XCTAssertEqual(a.publishTime, 0)
        XCTAssertNil(a.thumbnailURL)
        XCTAssertTrue(a.relatedTickers.isEmpty)
    }

    func testMissingUUIDThrows() {
        let noID = #"{"title": "no id"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(NewsArticle.self, from: noID))
    }
}
