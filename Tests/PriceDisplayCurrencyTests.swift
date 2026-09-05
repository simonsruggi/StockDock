import XCTest
@testable import StockDock

/// Covers issue #24: a converted price and its currency symbol are decided
/// together, so a figure is never shown under a currency it isn't in.
@MainActor
final class PriceDisplayCurrencyTests: XCTestCase {

    private var savedPriceCurrency = ""
    private var savedWatchlist: [String] = []

    override func setUp() {
        super.setUp()
        savedPriceCurrency = StorageService.shared.stockPriceCurrency
        savedWatchlist = StorageService.shared.watchlist
        StockService.shared.exchangeRates.removeAll()
    }

    override func tearDown() {
        StorageService.shared.stockPriceCurrency = savedPriceCurrency
        StorageService.shared.watchlist = savedWatchlist
        StockService.shared.exchangeRates.removeAll()
        super.tearDown()
    }

    // MARK: - priceDisplay

    /// "Original" — every stock stays in its own currency, untouched.
    func testOriginalCurrencyLeavesPricesAlone() {
        StorageService.shared.stockPriceCurrency = ""
        let usd = StockService.shared.priceDisplay(for: "USD")
        XCTAssertEqual(usd.rate, 1.0)
        XCTAssertEqual(usd.currency, "USD")
    }

    /// A stock already quoted in the target currency needs no rate.
    func testSameCurrencyNeedsNoRate() {
        StorageService.shared.stockPriceCurrency = "EUR"
        let eur = StockService.shared.priceDisplay(for: "EUR")
        XCTAssertEqual(eur.rate, 1.0)
        XCTAssertEqual(eur.currency, "EUR")
    }

    func testConvertsWhenTheRateIsKnown() {
        StorageService.shared.stockPriceCurrency = "EUR"
        StockService.shared.exchangeRates["USDEUR"] = 0.92
        let usd = StockService.shared.priceDisplay(for: "USD")
        XCTAssertEqual(usd.rate, 0.92)
        XCTAssertEqual(usd.currency, "EUR")
        // A $190 stock reads €174.80, not €190.
        XCTAssertEqual(190 * usd.rate, 174.8, accuracy: 0.0001)
    }

    /// The regression itself: with no rate loaded, the old code multiplied by a
    /// silent 1.0 and still labelled the figure with the target symbol, so a
    /// $190 stock read "€190". The price must fall back to its own currency.
    func testMissingRateFallsBackToTheStocksOwnCurrency() {
        StorageService.shared.stockPriceCurrency = "EUR"
        // exchangeRates is empty — exactly the state right after switching
        // currency in Settings, which clears it before refetching.
        let usd = StockService.shared.priceDisplay(for: "USD")
        XCTAssertEqual(usd.rate, 1.0)
        XCTAssertEqual(usd.currency, "USD", "an unconverted figure must keep its own currency")
    }

    /// Once the rate lands, the same call converts — no further action needed.
    func testDisplaySwitchesOverWhenTheRateArrives() {
        StorageService.shared.stockPriceCurrency = "EUR"
        XCTAssertEqual(StockService.shared.priceDisplay(for: "USD").currency, "USD")
        StockService.shared.exchangeRates["USDEUR"] = 0.92
        XCTAssertEqual(StockService.shared.priceDisplay(for: "USD").currency, "EUR")
    }

    /// `priceRate` keeps its old meaning for callers that only need the number.
    func testPriceRateStillReturnsTheMultiplier() {
        StorageService.shared.stockPriceCurrency = "EUR"
        StockService.shared.exchangeRates["USDEUR"] = 0.92
        XCTAssertEqual(StockService.shared.priceRate(from: "USD"), 0.92)
        XCTAssertEqual(StockService.shared.priceRate(from: "GBP"), 1.0, "unknown pair: no conversion")
    }

    // MARK: - Manual watchlist order (issue #23)

    func testMoveUpAndDown() {
        StorageService.shared.watchlist = ["AAPL", "MSFT", "TSLA"]
        XCTAssertTrue(StorageService.shared.moveWatchlistItem("TSLA", by: -1))
        XCTAssertEqual(StorageService.shared.watchlist, ["AAPL", "TSLA", "MSFT"])
        XCTAssertTrue(StorageService.shared.moveWatchlistItem("AAPL", by: 1))
        XCTAssertEqual(StorageService.shared.watchlist, ["TSLA", "AAPL", "MSFT"])
    }

    func testMoveStopsAtTheEnds() {
        StorageService.shared.watchlist = ["AAPL", "MSFT"]
        XCTAssertFalse(StorageService.shared.moveWatchlistItem("AAPL", by: -1))
        XCTAssertFalse(StorageService.shared.moveWatchlistItem("MSFT", by: 1))
        XCTAssertEqual(StorageService.shared.watchlist, ["AAPL", "MSFT"], "order is untouched at the ends")
    }

    func testMoveIgnoresUnknownSymbols() {
        StorageService.shared.watchlist = ["AAPL"]
        XCTAssertFalse(StorageService.shared.moveWatchlistItem("NFLX", by: 1))
        XCTAssertEqual(StorageService.shared.watchlist, ["AAPL"])
    }

    func testDragReorderMovesTheStoredOrder() {
        StorageService.shared.watchlist = ["AAPL", "MSFT", "TSLA"]
        // Drag the last row to the top, as `List`'s onMove reports it.
        StorageService.shared.moveWatchlistItem(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(StorageService.shared.watchlist, ["TSLA", "AAPL", "MSFT"])
    }
}
