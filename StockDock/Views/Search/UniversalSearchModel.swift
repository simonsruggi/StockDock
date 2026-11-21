import Foundation

/// State of one search box: the query, the merged local + market results and
/// the keyboard selection. One per surface (popover, desktop palette).
@MainActor
final class UniversalSearchModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { queryChanged() } } }
    @Published private(set) var items: [SearchItem] = []
    @Published private(set) var isSearchingMarket = false
    @Published var selectedIndex = 0

    let surface: SearchRouter.Surface
    private var marketItems: [SearchItem] = []
    private var marketTask: Task<Void, Never>?
    private weak var storage: StorageService?
    private weak var stocks: StockService?

    init(surface: SearchRouter.Surface) {
        self.surface = surface
    }

    func attach(storage: StorageService, stocks: StockService) {
        self.storage = storage
        self.stocks = stocks
        rebuild()
    }

    var selected: SearchItem? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + items.count) % items.count
    }

    func activate(_ item: SearchItem? = nil) {
        guard let item = item ?? selected else { return }
        SearchRouter.shared.send(item.target, from: surface)
        reset()
    }

    func reset() {
        marketTask?.cancel()
        marketItems = []
        isSearchingMarket = false
        query = ""
        rebuild()
    }

    private func queryChanged() {
        marketTask?.cancel()
        marketItems = []
        selectedIndex = 0
        rebuild()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, let stocks else { isSearchingMarket = false; return }
        isSearchingMarket = true
        // Wait for a pause in typing before asking Yahoo.
        marketTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let found = await stocks.search(query: q)
            guard !Task.isCancelled, let self else { return }
            self.applyMarket(found, query: q)
        }
    }

    private func applyMarket(_ found: [SearchResult], query q: String) {
        let watched = Set(storage?.watchlist ?? [])
        marketItems = found.filter { !watched.contains($0.symbol) }.prefix(SearchIndex.perSection).enumerated().map { index, r in
            SearchItem(id: "market.\(r.symbol)", section: .market, title: r.symbol,
                       subtitle: [r.name, r.exchange].filter { !$0.isEmpty }.joined(separator: " · "),
                       icon: "plus.circle", target: .addSymbol(r.symbol), score: 100 - index)
        }
        isSearchingMarket = false
        let keep = selected?.id
        rebuild()
        if let keep, let index = items.firstIndex(where: { $0.id == keep }) { selectedIndex = index }
    }

    private func rebuild() {
        guard let storage, let stocks else { items = []; return }
        items = SearchIndex.results(for: query, storage: storage, stocks: stocks, inWindow: surface == .window) + marketItems
        if selectedIndex >= items.count { selectedIndex = max(items.count - 1, 0) }
    }
}
