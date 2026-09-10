import XCTest
@testable import StockDock

final class AlertEvaluatorTests: XCTestCase {

    // MARK: - Disabled / invalid

    func testDisabledAlertNeverFires() {
        XCTAssertFalse(AlertEvaluator.shouldFire(
            condition: .priceAbove, threshold: 100, isEnabled: false,
            price: 200, changePercent: 0, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil))
    }

    func testZeroPriceNeverFires() {
        XCTAssertFalse(AlertEvaluator.shouldFire(
            condition: .priceBelow, threshold: 100, isEnabled: true,
            price: 0, changePercent: 0, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil))
    }

    // MARK: - Price above / below

    func testPriceAboveFiresAtAndOverThreshold() {
        let f: (Double) -> Bool = {
            AlertEvaluator.shouldFire(condition: .priceAbove, threshold: 200, isEnabled: true,
                                      price: $0, changePercent: 0, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil)
        }
        XCTAssertFalse(f(199.99))
        XCTAssertTrue(f(200.0))   // boundary inclusive
        XCTAssertTrue(f(250.0))
    }

    func testPriceBelowFiresAtAndUnderThreshold() {
        let f: (Double) -> Bool = {
            AlertEvaluator.shouldFire(condition: .priceBelow, threshold: 50, isEnabled: true,
                                      price: $0, changePercent: 0, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil)
        }
        XCTAssertFalse(f(50.01))
        XCTAssertTrue(f(50.0))    // boundary inclusive
        XCTAssertTrue(f(10.0))
    }

    // MARK: - Daily change

    func testDailyChangeUp() {
        let f: (Double) -> Bool = {
            AlertEvaluator.shouldFire(condition: .dailyChangeUp, threshold: 5, isEnabled: true,
                                      price: 100, changePercent: $0, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil)
        }
        XCTAssertFalse(f(4.9))
        XCTAssertTrue(f(5.0))
        XCTAssertTrue(f(8.0))
        XCTAssertFalse(f(-8.0))
    }

    func testDailyChangeDownUsesNegativeThreshold() {
        let f: (Double) -> Bool = {
            AlertEvaluator.shouldFire(condition: .dailyChangeDown, threshold: 5, isEnabled: true,
                                      price: 100, changePercent: $0, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: nil)
        }
        XCTAssertFalse(f(-4.9))
        XCTAssertTrue(f(-5.0))
        XCTAssertTrue(f(-9.0))
        XCTAssertFalse(f(9.0))
    }

    // MARK: - 52-week proximity

    func testNear52WeekHigh() {
        // high = 100, within 2% → fires at price >= 98
        let f: (Double) -> Bool = {
            AlertEvaluator.shouldFire(condition: .near52WeekHigh, threshold: 2, isEnabled: true,
                                      price: $0, changePercent: 0, fiftyTwoWeekHigh: 100, fiftyTwoWeekLow: 40)
        }
        XCTAssertFalse(f(97.99))
        XCTAssertTrue(f(98.0))   // boundary
        XCTAssertTrue(f(100.0))
    }

    func testNear52WeekLow() {
        // low = 40, within 2% → fires at price <= 40.8
        let f: (Double) -> Bool = {
            AlertEvaluator.shouldFire(condition: .near52WeekLow, threshold: 2, isEnabled: true,
                                      price: $0, changePercent: 0, fiftyTwoWeekHigh: 100, fiftyTwoWeekLow: 40)
        }
        XCTAssertFalse(f(40.81))
        XCTAssertTrue(f(40.8))   // boundary
        XCTAssertTrue(f(35.0))
    }

    func testNear52WeekMissingDataDoesNotFire() {
        XCTAssertFalse(AlertEvaluator.shouldFire(
            condition: .near52WeekHigh, threshold: 2, isEnabled: true,
            price: 100, changePercent: 0, fiftyTwoWeekHigh: nil, fiftyTwoWeekLow: 40))
        XCTAssertFalse(AlertEvaluator.shouldFire(
            condition: .near52WeekLow, threshold: 2, isEnabled: true,
            price: 100, changePercent: 0, fiftyTwoWeekHigh: 100, fiftyTwoWeekLow: nil))
    }

    // MARK: - StockQuote convenience uses effectivePrice

    func testConvenienceUsesEffectivePriceForExtendedHours() {
        // Regular price 100, post-market 210 → priceAbove 200 should fire on post price.
        let quote = makeQuote(price: 100, marketState: "POST", postMarketPrice: 210,
                              fiftyTwoWeekHigh: 250, fiftyTwoWeekLow: 50)
        let alert = PriceAlert(symbol: "AAPL", condition: .priceAbove, threshold: 200)
        XCTAssertTrue(AlertEvaluator.shouldFire(alert, quote: quote))
    }

    // MARK: - Stale previous-close must not fire during extended hours (bug repro)

    /// Pre-market with no pre-market price yet: `price` is the PREVIOUS regular close.
    /// An alert must NOT fire against that stale close — otherwise we get the
    /// spurious "drops below 1100 — now 1100" notification seen in production.
    func testPreMarketWithoutPreMarketPriceDoesNotFireOnPreviousClose() {
        let quote = makeQuote(price: 1100, marketState: "PRE", preMarketPrice: nil)
        let alert = PriceAlert(symbol: "MU", condition: .priceBelow, threshold: 1100)
        XCTAssertFalse(AlertEvaluator.shouldFire(alert, quote: quote),
                       "Alert fired on the stale previous close instead of waiting for pre-market data")
    }

    /// Same for a priceAbove alert during pre-market with no pre-market data.
    func testPreMarketWithoutPreMarketPriceDoesNotFireAbove() {
        let quote = makeQuote(price: 1100, marketState: "PRE", preMarketPrice: nil)
        let alert = PriceAlert(symbol: "MU", condition: .priceAbove, threshold: 1050)
        XCTAssertFalse(AlertEvaluator.shouldFire(alert, quote: quote))
    }

    /// Once real pre-market data is present, alerts fire against it normally.
    func testPreMarketWithPreMarketPriceFiresOnPreMarketValue() {
        let dip = makeQuote(price: 1100, marketState: "PRE", preMarketPrice: 1098)
        XCTAssertTrue(AlertEvaluator.shouldFire(
            PriceAlert(symbol: "MU", condition: .priceBelow, threshold: 1100), quote: dip))

        let rise = makeQuote(price: 1100, marketState: "PRE", preMarketPrice: 1211.38)
        XCTAssertTrue(AlertEvaluator.shouldFire(
            PriceAlert(symbol: "MU", condition: .priceAbove, threshold: 1200), quote: rise))
    }

    /// Post-market with no post price yet must likewise not fire on the close.
    func testPostMarketWithoutPostMarketPriceDoesNotFire() {
        let quote = makeQuote(price: 1100, marketState: "POST", postMarketPrice: nil)
        let alert = PriceAlert(symbol: "MU", condition: .priceBelow, threshold: 1100)
        XCTAssertFalse(AlertEvaluator.shouldFire(alert, quote: quote))
    }

    /// When the market is fully CLOSED, `price` IS today's real close — alerts
    /// should still be able to fire against it.
    func testClosedMarketStillFiresOnRegularClose() {
        let quote = makeQuote(price: 1100, marketState: "CLOSED", postMarketPrice: nil)
        let alert = PriceAlert(symbol: "MU", condition: .priceBelow, threshold: 1100)
        XCTAssertTrue(AlertEvaluator.shouldFire(alert, quote: quote))
    }

    // MARK: - Helpers

    // MARK: - Grouping by symbol (Settings list)

    func testGroupedBySymbolKeepsFirstAppearanceOrderAndSortsThresholds() {
        let alerts = [
            PriceAlert(symbol: "MU", condition: .priceAbove, threshold: 1020),
            PriceAlert(symbol: "AAPL", condition: .priceBelow, threshold: 150),
            PriceAlert(symbol: "MU", condition: .priceAbove, threshold: 1010),
            PriceAlert(symbol: "MU", condition: .priceBelow, threshold: 900),
        ]
        let groups = PriceAlert.groupedBySymbol(alerts)
        XCTAssertEqual(groups.map(\.symbol), ["MU", "AAPL"])
        XCTAssertEqual(groups[0].alerts.map(\.threshold), [1010, 1020, 900])
        XCTAssertEqual(groups[1].alerts.count, 1)
    }

    func testGroupedByConditionSplitsAboveAndBelowInOrder() {
        let alerts = [
            PriceAlert(symbol: "MU", condition: .priceBelow, threshold: 900),
            PriceAlert(symbol: "MU", condition: .priceAbove, threshold: 1020),
            PriceAlert(symbol: "MU", condition: .priceAbove, threshold: 1010),
        ]
        let groups = PriceAlert.groupedByCondition(alerts)
        XCTAssertEqual(groups.map(\.condition), [.priceAbove, .priceBelow])
        XCTAssertEqual(groups[0].alerts.map(\.threshold), [1010, 1020])
        XCTAssertEqual(groups[1].alerts.map(\.threshold), [900])
    }

    func testDuplicateIsFreshArmedCopy() {
        let original = PriceAlert(symbol: "MU", condition: .priceAbove, threshold: 1010,
                                  isEnabled: false, lastTriggeredAt: Date())
        let copy = original.duplicate(condition: .priceBelow, threshold: 900)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.symbol, "MU")
        XCTAssertEqual(copy.condition, .priceBelow)
        XCTAssertEqual(copy.threshold, 900)
        XCTAssertTrue(copy.isEnabled)
        XCTAssertNil(copy.lastTriggeredAt)
    }

    func testDescribeShortOmitsPriceWording() {
        let a = PriceAlert(symbol: "MU", condition: .priceAbove, threshold: 1010)
        XCTAssertTrue(AlertEvaluator.describeShort(a, currencySymbol: "$").hasPrefix("Above $"))
        let b = PriceAlert(symbol: "MU", condition: .priceBelow, threshold: 900)
        XCTAssertTrue(AlertEvaluator.describeShort(b, currencySymbol: "$").hasPrefix("Below $"))
    }

    private func makeQuote(price: Double,
                           changePercent: Double = 0,
                           marketState: String = "REGULAR",
                           preMarketPrice: Double? = nil,
                           postMarketPrice: Double? = nil,
                           fiftyTwoWeekHigh: Double? = nil,
                           fiftyTwoWeekLow: Double? = nil) -> StockQuote {
        StockQuote(symbol: "AAPL", name: "Apple", price: price, change: 0,
                   changePercent: changePercent, currency: "USD", marketState: marketState,
                   dayHigh: nil, dayLow: nil,
                   fiftyTwoWeekHigh: fiftyTwoWeekHigh, fiftyTwoWeekLow: fiftyTwoWeekLow,
                   preMarketPrice: preMarketPrice, preMarketChange: nil, preMarketChangePercent: nil,
                   postMarketPrice: postMarketPrice, postMarketChange: nil, postMarketChangePercent: nil)
    }
}
