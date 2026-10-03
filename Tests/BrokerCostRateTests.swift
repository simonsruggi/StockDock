import XCTest
@testable import StockDock

/// The exchange rate a cost was booked at travels with the holding through
/// export and import, and values the cost exactly as it was paid.
@MainActor
final class BrokerCostRateTests: XCTestCase {

    func testImportKeepsTheBrokerRate() throws {
        let s = StorageService.shared
        let p = Portfolio(name: "Broker", holdings: [
            Holding(symbol: "GOOGL", quantity: 74, avgPrice: 340.65, costRate: 1 / 1.1356, costRateCurrency: "EUR")
        ])
        let imported = try XCTUnwrap(s.importPortfolios(from: try XCTUnwrap(s.exportPortfolios([p]))))
        let h = imported[0].holdings[0]
        XCTAssertEqual(h.costBasisLocal * (try XCTUnwrap(h.purchaseRate(to: "EUR"))), 22198.05, accuracy: 0.01)
    }

    func testPurchaseRateOnlyForItsCurrency() {
        let h = Holding(symbol: "MU", quantity: 1, avgPrice: 1000, costRate: 0.88, costRateCurrency: "EUR")
        XCTAssertEqual(h.purchaseRate(to: "EUR"), 0.88)
        XCTAssertNil(h.purchaseRate(to: "USD"))
        XCTAssertNil(Holding(symbol: "MU", quantity: 1, avgPrice: 1000).purchaseRate(to: "EUR"))
    }

    func testEditingPriceOrDateDropsTheBrokerRate() {
        let s = StorageService.shared
        let saved = s.portfolios
        defer { s.portfolios = saved }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let hid = UUID(), pid = UUID()
        s.portfolios = [Portfolio(id: pid, name: "P", holdings: [
            Holding(id: hid, symbol: "MU", quantity: 16, avgPrice: 1068.9, purchaseDate: date, costRate: 0.88, costRateCurrency: "EUR")
        ])]

        s.updateHolding(in: pid, holdingId: hid, quantity: 20, avgPrice: 1068.9, purchaseDate: date)
        XCTAssertEqual(s.portfolios[0].holdings[0].costRate, 0.88, "quantity alone keeps it")

        s.updateHolding(in: pid, holdingId: hid, quantity: 20, avgPrice: 1000, purchaseDate: date)
        XCTAssertNil(s.portfolios[0].holdings[0].costRate)
        XCTAssertNil(s.portfolios[0].holdings[0].costRateCurrency)
    }
}
