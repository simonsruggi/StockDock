import SwiftUI

/// DS-styled search to add symbols to the watchlist.
struct WatchlistSearchSheet: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private var looksLikeISIN: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.count == 12 && q.prefix(2).allSatisfy(\.isLetter) && q.dropFirst(2).allSatisfy { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Add to watchlist").font(DS.titleXL).tracking(-0.3).foregroundStyle(DS.ink)
                Spacer()
                Button("Done", action: onDismiss).buttonStyle(.plain)
                    .font(.inter(12, weight: .medium, relativeTo: .body)).foregroundStyle(DS.brand)
                    .keyboardShortcut(.cancelAction)
            }
            DSTextField(placeholder: "Symbol, name or ISIN (e.g. AAPL, Tesla)", text: $query)
                .onChange(of: query) { _, new in runSearch(new) }

            if isSearching {
                HStack { Spacer(); DSSpinner(size: 20); Spacer() }.frame(height: 120)
            } else if results.isEmpty && query.count >= 2 {
                Text("No results").font(DS.caption).foregroundStyle(DS.inkSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(results) { r in
                            Button { add(r) } label: { resultRow(r) }
                                .buttonStyle(.plain)
                            if r.id != results.last?.id {
                                Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(24)
        .frame(width: 480)
        .frame(minHeight: 260)
        .background(DS.ground)
    }

    private func resultRow(_ r: SearchResult) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.symbol).font(DS.figure).foregroundStyle(DS.ink)
                Text(r.name).font(DS.micro).foregroundStyle(DS.inkTertiary).lineLimit(1)
            }
            Spacer()
            if let q = stockService.quotes[r.symbol] {
                Text("\(q.price.formatted(.number.precision(.fractionLength(2)))) \(q.currency)")
                    .font(DS.figure).foregroundStyle(DS.inkSecondary)
            }
            if !r.type.isEmpty { Tag(text: r.type.uppercased(), color: DS.inkTertiary) }
            if storageService.watchlist.contains(r.symbol) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.up).font(.system(size: 12))
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        guard q.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearching = true
            let res = await stockService.search(query: q)
            guard !Task.isCancelled else { return }
            results = res; isSearching = false
            let symbols = res.map(\.symbol)
            if !symbols.isEmpty { await stockService.fetchQuotes(symbols: symbols) }
        }
    }

    private func add(_ r: SearchResult) {
        storageService.addToWatchlist(r.symbol)
        if !r.type.isEmpty { storageService.setType(r.type, for: r.symbol) }
        if looksLikeISIN { storageService.setISIN(query.trimmingCharacters(in: .whitespaces).uppercased(), for: r.symbol) }
        Task { await stockService.fetchQuotes(symbols: [r.symbol]) }
    }
}
