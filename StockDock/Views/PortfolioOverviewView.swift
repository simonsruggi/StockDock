import SwiftUI

struct PortfolioOverviewView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @ObservedObject var allHoursService = HyperliquidService.shared
    @Environment(\.editHoldingAction) var editHoldingAction
    @Environment(\.addHoldingAction) var addHoldingAction
    @Environment(\.portfolioActions) private var portfolioActions
    let scope: PortfolioWindowView.Scope

    /// Hero chart range — a pure UI filter over the value series.
    enum ChartRange: String, CaseIterable {
        case day = "24H", week = "7D", month = "1M", year = "1Y", all = "All"
        var days: Int? {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .year: return 365
            case .all: return nil
            }
        }
        /// Suffix for the hero pill, describing the span it measures.
        var changeLabel: String {
            switch self {
            case .day: return "today"
            case .week: return "past 7d"
            case .month: return "past 1M"
            case .year: return "past 1Y"
            case .all: return "all-time"
            }
        }
    }
    /// #14: seeded from the last range the user picked (see `restoreRange`), so
    /// the chart opens where they left it instead of always on All.
    @State var chartRange: ChartRange = .all
    /// Applies the remembered range, if there is a valid one stored.
    private func restoreRange() {
        if let saved = ChartRange(rawValue: storageService.lastPortfolioChartRange) {
            chartRange = saved
        }
    }

    /// Key of the range load in flight; the chart shows a spinner instead of the
    /// empty-history message while it is set.
    @State var loadingRangeKey: String?
    var isLoadingRange: Bool { loadingRangeKey != nil }

    @State var hoveredSlice: String?
    @State var hoverPoint: ValuePoint?

    var portfolios: [Portfolio] {
        switch scope {
        // #14: the combined view shows only what counts toward the total; opening
        // an excluded portfolio directly still shows it in full.
        case .all: return storageService.countedPortfolios
        case .portfolio(let id): return storageService.portfolios.filter { $0.id == id }
        }
    }

    var title: String {
        switch scope {
        case .all: return "Portfolio"
        case .portfolio(let id): return storageService.portfolios.first { $0.id == id }?.name ?? "Portfolio"
        }
    }

    var currencySymbol: String { StorageService.currencySymbol(for: storageService.preferredCurrency) }
    var decimals: Int { storageService.percentDecimals }

    private var symbols: [String] { Array(Set(portfolios.flatMap { $0.holdings.map(\.symbol) })).sorted() }

    var body: some View {
        // Valued ONCE per render, then threaded into every section (see `Derived`).
        let d = derived
        return PageScaffold(title, caption: "\(d.holdings.count) positions · \(storageService.preferredCurrency)") {
            HStack(spacing: 12) {
                portfolioMenu
                RefreshButton(isLoading: stockService.isLoading) {
                    Task { await stockService.refreshAll(storageService: storageService) }
                }
            }
        } content: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.gap) {
                        heroCard(d)
                        statRow(d)
                        HStack(alignment: .top, spacing: DS.gap) {
                            allocationCard(d).frame(maxWidth: .infinity)
                            moversCard(proxy: proxy, d).frame(width: 340)
                        }
                        positionsCard(d).id("positions")
                    }
                    .pageColumn()
                    .padding(.top, 4)
                }
            }
        }
        .navigationTitle(title)
        .task(id: symbols) {
            let service = stockService
            await withTaskGroup(of: Void.self) { group in
                for s in symbols { group.addTask { await service.ensurePriceHistory(for: s) } }
            }
        }
        .task(id: rangeLoadKey) {
            let key = rangeLoadKey
            loadingRangeKey = key
            defer { if loadingRangeKey == key { loadingRangeKey = nil } }
            let service = stockService
            let range = chartRange
            let extended = storageService.showExtendedHours
            await withTaskGroup(of: Void.self) { group in
                for s in symbols {
                    group.addTask {
                        switch range {
                        case .day:
                            if extended { await service.ensureIntradayExtended(for: s) } else { await service.ensureIntraday(for: s) }
                        case .week: await service.ensureIntradayWeek(for: s)
                        case .month, .year: await service.ensurePriceHistory(for: s)
                        case .all:
                            await service.ensurePriceHistory(for: s)
                            await service.ensurePriceHistoryMax(for: s)
                        }
                    }
                }
            }
        }
    }

    private var rangeLoadKey: String {
        "\(symbols.joined(separator: ","))-\(chartRange.rawValue)-\(storageService.showExtendedHours)"
    }

    var rangePicker: some View {
        SegmentedRangePicker(options: ChartRange.allCases, label: \.rawValue, selection: $chartRange)
            .onAppear(perform: restoreRange)
            .onChange(of: chartRange) { _, new in
                storageService.lastPortfolioChartRange = new.rawValue
            }
    }

    /// The same actions as the sidebar right-click, as a header "⋯" menu — shown
    /// only when viewing a single portfolio.
    @ViewBuilder private var portfolioMenu: some View {
        if case .portfolio(let id) = scope, let p = portfolios.first {
            DSMenu(sections: [
                [ DSMenuAction(title: "Add Holding…", icon: "plus") { portfolioActions.addHolding(id) },
                  DSMenuAction(title: "Rename…", icon: "pencil") { portfolioActions.rename(id, p.name) },
                  DSMenuAction(title: "Notifications…", icon: "bell") { portfolioActions.notifications(id, p.name) },
                  DSMenuAction(title: "Export…", icon: "square.and.arrow.up") { portfolioActions.export(p) } ],
                [ DSMenuAction(title: "Delete Portfolio", icon: "trash", destructive: true) { portfolioActions.delete(id) } ],
            ]) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(DS.cardAlt))
            }
            .help("Portfolio actions — add holding, rename, notifications, export, delete")
        }
    }
}
