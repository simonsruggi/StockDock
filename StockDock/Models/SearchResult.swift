import Foundation

struct SearchResult: Identifiable, Codable {
    let symbol: String
    let name: String
    let exchange: String
    let type: String

    var id: String { symbol }

    private enum CodingKeys: String, CodingKey {
        case symbol
        case name = "longname"
        case exchange
        case type = "quoteType"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        exchange = try container.decodeIfPresent(String.self, forKey: .exchange) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    }

    init(symbol: String, name: String, exchange: String, type: String) {
        self.symbol = symbol
        self.name = name
        self.exchange = exchange
        self.type = type
    }
}
