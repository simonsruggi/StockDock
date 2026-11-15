import XCTest
@testable import StockDock

/// Covers decoding of Yahoo's batched `/v8/finance/spark` response, which fills
/// the watchlist sparklines. Yahoo changed the shape; both must keep working.
final class SparkParsingTests: XCTestCase {

    func testDecodesCurrentFlatShape() {
        let json = """
        {"NVDA": {"symbol": "NVDA", "timestamp": [1000, 2000, 3000], "close": [10.0, null, 12.0],
                  "chartPreviousClose": 9.5, "dataGranularity": 300},
         "GC=F": {"symbol": "GC=F", "timestamp": [1000, 2000], "close": [3800.0, 3810.5]}}
        """
        let result = StockService.sparkPoints(from: Data(json.utf8))
        XCTAssertEqual(Set(result.keys), ["NVDA", "GC=F"])
        XCTAssertEqual(result["NVDA"]?.map(\.close), [10.0, 12.0])
        XCTAssertEqual(result["GC=F"]?.count, 2)
    }

    func testDecodesLegacyWrappedShape() {
        let json = """
        {"spark": {"result": [{"symbol": "AAPL", "response": [{
            "meta": {"symbol": "AAPL", "regularMarketPrice": 12.0},
            "timestamp": [1000, 2000],
            "indicators": {"quote": [{"close": [11.0, 12.0]}]}
        }]}]}}
        """
        let result = StockService.sparkPoints(from: Data(json.utf8))
        XCTAssertEqual(result["AAPL"]?.map(\.close), [11.0, 12.0])
    }

    func testUnreadableResponseYieldsNothing() {
        XCTAssertTrue(StockService.sparkPoints(from: Data("Edge: Too Many Requests".utf8)).isEmpty)
    }
}
