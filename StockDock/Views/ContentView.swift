import SwiftUI

enum Tab: String, CaseIterable {
    case home = "Home"
    case watchlist = "Watchlist"
    case portfolios = "Portfolios"
    case settings = "Settings"
}

extension Tab {
    var icon: String {
        switch self {
        case .home: return "newspaper"
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

/// Injected by AppDelegate so the popover opens the desktop window by calling
/// AppDelegate directly — no fragile `NSApp.delegate as? AppDelegate` cast that
/// can silently fail in a SwiftUI app.
private struct OpenWindowActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {
        NSLog("[StockDock] Open tapped but no openWindowAction was injected")
    }
}

/// The per-portfolio actions (same as the sidebar right-click menu), injected by
/// AppDelegate/PortfolioWindowView so the Overview header can offer them too.
struct PortfolioActions {
    var addHolding: (UUID) -> Void = { _ in }
    var rename: (UUID, String) -> Void = { _, _ in }
    var notifications: (UUID, String) -> Void = { _, _ in }
    var export: (Portfolio) -> Void = { _ in }
    var delete: (UUID) -> Void = { _ in }
}

private struct PortfolioActionsKey: EnvironmentKey {
    static let defaultValue = PortfolioActions()
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
    var openWindowAction: () -> Void {
        get { self[OpenWindowActionKey.self] }
        set { self[OpenWindowActionKey.self] = newValue }
    }
    var portfolioActions: PortfolioActions {
        get { self[PortfolioActionsKey.self] }
        set { self[PortfolioActionsKey.self] = newValue }
    }
}

struct ContentView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Environment(\.openWindowAction) private var openWindowAction
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
                HStack(spacing: 7) {
                    BrandMark(size: 22)
                    Text("StockDock")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(DS.ink)
                    Text(appVersion)
                        .font(.inter(10, weight: .medium, relativeTo: .caption2))
                        .foregroundColor(.secondary)
                    // Dev builds ship without a Sparkle feed URL — flag them so a dev
                    // window is never mistaken for the released app.
                    if Bundle.main.infoDictionary?["SUFeedURL"] == nil {
                        Text("DEV")
                            .font(.inter(8, weight: .bold, relativeTo: .caption2))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(DS.gold))
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
                        if selectedTab == .home {
                            await stockService.refreshNews(storageService: storageService, force: true)
                        }
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.inter(12, relativeTo: .callout))
                }
                .buttonStyle(.borderless)
                .disabled(stockService.isLoading)

                // The clear way into the full desktop app.
                Button(action: {
                    NSLog("[StockDock] Open button tapped in popover")
                    openWindowAction()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                        Text("Open")
                    }
                    .font(.inter(11, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(DS.brand))
                }
                .buttonStyle(.plain)
                .help("Open the full StockDock window")

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
                Text("Home").tag(Tab.home)
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
                case .home:
                    HomeView()
                case .watchlist:
                    WatchlistView(showSearch: $showSearch)
                case .portfolios:
                    PortfolioListView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.ground)
        }
        .tint(DS.brand)
        .environment(\.addHoldingAction, AddHoldingAction { portfolioId in
            addHoldingPortfolioId = portfolioId
        })
        .environment(\.editHoldingAction, EditHoldingAction { portfolioId, holding in
            editHolding = (portfolioId, holding)
        })
        // Issue #7: in-app language override. Reactive because ContentView observes
        // storageService, so changing the language re-applies the locale to all children.
        .environment(\.locale, Locale(identifier: storageService.appLanguage))
    }
}
