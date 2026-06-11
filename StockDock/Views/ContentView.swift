import SwiftUI

enum Tab: String, CaseIterable {
    case watchlist = "Watchlist"
    case portfolios = "Portfolios"
    case settings = "Settings"
}

extension Tab {
    var icon: String {
        switch self {
        case .watchlist: return "list.bullet"
        case .portfolios: return "briefcase"
        case .settings: return "gear"
        }
    }
}

// Environment keys for navigation from child views
struct AddHoldingAction {
    let perform: (UUID) -> Void
}

struct EditHoldingAction {
    let perform: (UUID, Holding) -> Void
}

private struct AddHoldingActionKey: EnvironmentKey {
    static let defaultValue = AddHoldingAction { _ in }
}

private struct EditHoldingActionKey: EnvironmentKey {
    static let defaultValue = EditHoldingAction { _, _ in }
}

extension EnvironmentValues {
    var addHoldingAction: AddHoldingAction {
        get { self[AddHoldingActionKey.self] }
        set { self[AddHoldingActionKey.self] = newValue }
    }
    var editHoldingAction: EditHoldingAction {
        get { self[EditHoldingActionKey.self] }
        set { self[EditHoldingActionKey.self] = newValue }
    }
}

struct ContentView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @State private var selectedTab: Tab = .watchlist
    @State private var showSearch = false
    @State private var addHoldingPortfolioId: UUID?
    @State private var editHolding: (portfolioId: UUID, holding: Holding)?

    var body: some View {
        Group {
            if showSearch {
                SearchView(mode: .watchlist, isPresented: $showSearch)
            } else if let portfolioId = addHoldingPortfolioId {
                AddHoldingView(portfolioId: portfolioId, isPresented: $addHoldingPortfolioId)
            } else if let edit = editHolding {
                EditHoldingView(portfolioId: edit.portfolioId, holding: edit.holding, isPresented: $editHolding)
            } else {
                mainContent
            }
        }
        .frame(width: 380, height: 520)
        .onAppear {
            selectedTab = Tab(rawValue: storageService.lastSelectedTab) ?? .watchlist
        }
        .onChange(of: selectedTab) { _, newValue in
            storageService.lastSelectedTab = newValue.rawValue
        }
    }

    /// Marketing version (CFBundleShortVersionString) prefixed with "v", e.g. "v1.5.1".
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Text("StockDock")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                        .fontWeight(.bold)
                    if Bundle.main.infoDictionary?["SUFeedURL"] == nil {
                        Text("DEV")
                            .font(.inter(8, weight: .bold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(.orange))
                    } else {
                        Text(appVersion)
                            .font(.inter(10, weight: .medium, relativeTo: .caption2))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if stockService.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                Button(action: {
                    Task {
                        await stockService.refreshAll(storageService: storageService)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.inter(12, relativeTo: .callout))
                }
                .buttonStyle(.borderless)
                .disabled(stockService.isLoading)

                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.inter(11, relativeTo: .subheadline))
                }
                .buttonStyle(.borderless)
                .help("Quit StockDock")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Watchlist").tag(Tab.watchlist)
                Text("Portfolios").tag(Tab.portfolios)
                Image(systemName: "gear").tag(Tab.settings)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .watchlist:
                    WatchlistView(showSearch: $showSearch)
                case .portfolios:
                    PortfolioListView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .environment(\.addHoldingAction, AddHoldingAction { portfolioId in
            addHoldingPortfolioId = portfolioId
        })
        .environment(\.editHoldingAction, EditHoldingAction { portfolioId, holding in
            editHolding = (portfolioId, holding)
        })
    }
}
