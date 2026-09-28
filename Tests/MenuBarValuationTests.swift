import XCTest
@testable import StockDock

/// The menu bar P&L must match the Portfolio window: same signed,
/// leverage-aware cost basis, same percentage on |cost|.
@MainActor
final class MenuBarValuationTests: XCTestCase {

    private var savedQuotes: [String: StockQuote] = [:]

    override func setUp() {
        super.setUp()
        savedQuotes = StockService.shared.quotes
    }

    override func tearDown() {
        StockService.shared.quotes = savedQuotes
        super.tearDown()
    }

    private func quote(_ symbol: String, price: Double) -> StockQuote {
        // Quoted in the preferred currency, so every FX rate is exactly 1.
        StockQuote(symbol: symbol, name: symbol, price: price, change: 0, changePercent: 0,
                   currency: StorageService.shared.preferredCurrency, marketState: "REGULAR",
                   dayHigh: nil, dayLow: nil, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil,
                   preMarketPrice: nil, preMarketChange: nil, preMarketChangePercent: nil,
                   postMarketPrice: nil, postMarketChange: nil, postMarketChangePercent: nil)
    }

    /// Window-side figures, computed exactly as `PortfolioWindowView` does.
    private func windowTotals(_ portfolios: [Portfolio]) -> (value: Double, cost: Double, pct: Double) {
        let t = PortfolioValuation.totals(PortfolioValuation.inputs(
            for: portfolios.flatMap { $0.holdings },
            stockService: StockService.shared, storageService: StorageService.shared))
        return (t.value, t.cost, PortfolioValuation.pnlPercent(value: t.value, cost: t.cost))
    }

    private func menuBar(_ portfolios: [Portfolio]) -> MenuBarPortfolioStats {
        AppDelegate.menuBarPortfolioStats(portfolios: portfolios,
                                          stockService: StockService.shared,
                                          storageService: StorageService.shared)
    }

    func testShortAndLeveragedPositionsMatchTheWindow() {
        StockService.shared.quotes["ZZSHORT"] = quote("ZZSHORT", price: 90)
        StockService.shared.quotes["ZZLEV"] = quote("ZZLEV", price: 110)
        let portfolios = [Portfolio(name: "Mixed", holdings: [
            // Short 10 @ 100, now 90 → +100 gain, cost basis -1000.
            Holding(symbol: "ZZSHORT", quantity: -10, avgPrice: 100),
            // Long 10 @ 100 at 3x, now 110 → +300 gain, cost basis 3000.
            Holding(symbol: "ZZLEV", quantity: 10, avgPrice: 100, leverage: 3),
        ])]

        let bar = menuBar(portfolios)
        let window = windowTotals(portfolios)

        XCTAssertEqual(bar.cost, 2000, accuracy: 1e-9)
        XCTAssertEqual(bar.pnl, 400, accuracy: 1e-9)
        XCTAssertEqual(bar.value, window.value, accuracy: 1e-9)
        XCTAssertEqual(bar.cost, window.cost, accuracy: 1e-9)
        XCTAssertEqual(bar.pnl, window.value - window.cost, accuracy: 1e-9)
        XCTAssertEqual(bar.pnlPercent, window.pct, accuracy: 1e-9)
        XCTAssertEqual(bar.pnlPercent, 20, accuracy: 1e-9)
    }

    /// A short-only book has a negative cost: the window still shows a
    /// percentage (on |cost|), so the menu bar must not collapse it to 0%.
    func testShortOnlyPortfolioPercentMatchesTheWindow() {
        StockService.shared.quotes["ZZSHORT"] = quote("ZZSHORT", price: 90)
        let portfolios = [Portfolio(name: "Short", holdings: [
            Holding(symbol: "ZZSHORT", quantity: -10, avgPrice: 100, leverage: 2),
        ])]

        let bar = menuBar(portfolios)
        let window = windowTotals(portfolios)

        XCTAssertEqual(bar.cost, window.cost, accuracy: 1e-9)
        XCTAssertEqual(bar.pnl, 200, accuracy: 1e-9)
        XCTAssertEqual(bar.pnlPercent, window.pct, accuracy: 1e-9)
        XCTAssertEqual(bar.pnlPercent, 10, accuracy: 1e-9)
    }
}
