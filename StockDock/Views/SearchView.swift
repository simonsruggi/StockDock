import SwiftUI

enum SearchMode {
    case watchlist
    case holding(portfolioId: UUID)
}

struct SearchView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    let mode: SearchMode
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Search")
                    .font(.inter(13, weight: .bold, relativeTo: .headline))
                Spacer()
                Button("Close") { isPresented = false }
                    .buttonStyle(.borderless)
            }
            .padding()

            TextField("Symbol, name or ISIN (e.g. AAPL, Tesla, IE00B4L5Y983)", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onChange(of: query) { _, newValue in
                    searchTask?.cancel()
                    guard newValue.count >= 2 else {
                        results = []
                        return
                    }
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        isSearching = true
                        let searchResults = await stockService.search(query: newValue)
                        guard !Task.isCancelled else { return }
                        results = searchResults
                        isSearching = false
                        // Fetch prices for search results
                        let symbols = searchResults.map(\.symbol)
                        if !symbols.isEmpty {
                            await stockService.fetchQuotes(symbols: symbols)
                        }
                    }
                }

            Divider()
                .padding(.top, 8)

            if isSearching {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if results.isEmpty && query.count >= 2 {
                Spacer()
                Text("No results")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(results) { result in
                    Button(action: { addResult(result) }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.symbol)
                                    .font(.inter(13, relativeTo: .body).monospacedDigit())
                                    .fontWeight(.semibold)
                                Text(result.name)
                                    .font(.inter(10, relativeTo: .caption))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()

                            if let quote = stockService.quotes[result.symbol] {
                                Text("\(quote.price.formatted(.number.precision(.fractionLength(2)))) \(quote.currency)")
                                    .font(.inter(13, relativeTo: .body).monospacedDigit())
                                    .foregroundColor(.primary)
                            }

                            Text(result.type.uppercased())
                                .font(.inter(8, weight: .medium, relativeTo: .caption2))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(.secondary))

                            Text(result.exchange)
                                .font(.inter(9, relativeTo: .caption2))
                                .foregroundColor(.secondary)

                            if isAlreadyAdded(result.symbol) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.inter(10, relativeTo: .caption))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queryLooksLikeISIN: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.count == 12 && q.prefix(2).allSatisfy(\.isLetter) && q.dropFirst(2).allSatisfy { $0.isLetter || $0.isNumber }
    }

    private func addResult(_ result: SearchResult) {
        switch mode {
        case .watchlist:
            storageService.addToWatchlist(result.symbol)
            if queryLooksLikeISIN {
                storageService.setISIN(query.trimmingCharacters(in: .whitespaces).uppercased(), for: result.symbol)
            }
            isPresented = false
            Task {
                await stockService.fetchQuotes(symbols: [result.symbol])
            }
        case .holding:
            // For holdings, we dismiss and the AddHoldingView handles it
            break
        }
    }

    private func isAlreadyAdded(_ symbol: String) -> Bool {
        switch mode {
        case .watchlist:
            return storageService.watchlist.contains(symbol)
        case .holding:
            return false
        }
    }
}
