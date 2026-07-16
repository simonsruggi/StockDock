import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The full-window companion to the menu-bar glance. It IS the app in expanded
/// form: same tabs as the popover (Home, Watchlist, Portfolios, Settings), same
/// data, over the same shared `StockService`/`StorageService` — so edits here
/// reflect in the menu bar instantly and vice versa. The look is the "private
/// banking" light editorial system: one uninterrupted paper surface under a
/// transparent titlebar, flat tinted sidebar, floating traffic lights.
struct PortfolioWindowView: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService
    @Namespace private var navNamespace

    /// Sidebar destinations — the dock tabs, with Portfolios expanded per portfolio.
    enum Nav: Hashable {
        case home, watchlist, portfoliosAll, settings
        case portfolio(UUID)
    }

    /// Scope passed to the portfolio overview.
    enum Scope: Hashable {
        case all
        case portfolio(UUID)
    }

    @State private var selection: Nav = PortfolioWindowView.initialSelection()

    /// Dev affordance: SD_OPEN_TAB=home|watchlist|settings preselects a tab so
    /// each pane can be screenshotted deterministically.
    static func initialSelection() -> Nav {
        switch ProcessInfo.processInfo.environment["SD_OPEN_TAB"] {
        case "home": return .home
        case "watchlist": return .watchlist
        case "settings": return .settings
        default: return .portfoliosAll
        }
    }
    @State private var showSearch = false
    @State private var addHoldingPortfolioId: UUID?
    @State private var editHolding: EditTarget?
    @State private var showNewPortfolio = false
    @State private var newPortfolioName = ""
    @State private var renameTarget: PortfolioRef?
    @State private var notifTarget: PortfolioRef?
    @State private var importAlert: String?

    /// Wraps the edit-holding tuple so it can drive a `.sheet(item:)`.
    struct EditTarget: Identifiable {
        let portfolioId: UUID
        let holding: Holding
        var id: UUID { holding.id }
    }
    struct PortfolioRef: Identifiable { let id: UUID; let name: String }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 224, ideal: 240, max: 280)
        } detail: {
            detail
                .frame(minWidth: 640)
                .id(selection)
                .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .animation(.easeOut(duration: 0.22), value: selection)
        .toolbar(removing: .sidebarToggle)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 1000, minHeight: 680)
        .environment(\.locale, Locale(identifier: storageService.appLanguage))
        .environment(\.addHoldingAction, AddHoldingAction { addHoldingPortfolioId = $0 })
        .environment(\.editHoldingAction, EditHoldingAction { editHolding = EditTarget(portfolioId: $0, holding: $1) })
        .environment(\.portfolioActions, PortfolioActions(
            addHolding: { addHoldingPortfolioId = $0 },
            rename: { renameTarget = PortfolioRef(id: $0, name: $1) },
            notifications: { notifTarget = PortfolioRef(id: $0, name: $1) },
            export: { exportPortfolios([$0]) },
            delete: { id in
                storageService.deletePortfolio(id: id)
                if selection == .portfolio(id) { selection = .portfoliosAll }
            }))
        .sheet(isPresented: $showSearch) {
            WatchlistSearchSheet { showSearch = false }
                .environmentObject(stockService).environmentObject(storageService)
        }
        .sheet(isPresented: Binding(get: { addHoldingPortfolioId != nil }, set: { if !$0 { addHoldingPortfolioId = nil } })) {
            if let id = addHoldingPortfolioId {
                HoldingFormSheet(mode: .add(portfolioId: id)) { addHoldingPortfolioId = nil }
                    .environmentObject(stockService).environmentObject(storageService)
            }
        }
        .sheet(item: $editHolding) { target in
            HoldingFormSheet(mode: .edit(portfolioId: target.portfolioId, holding: target.holding)) { editHolding = nil }
                .environmentObject(stockService).environmentObject(storageService)
        }
        .sheet(isPresented: $showNewPortfolio) { newPortfolioSheet }
        .sheet(item: $renameTarget) { t in
            RenamePortfolioSheet(portfolioId: t.id, currentName: t.name) { renameTarget = nil }
                .environmentObject(storageService)
        }
        .sheet(item: $notifTarget) { t in
            PortfolioNotificationsSheet(portfolioId: t.id, portfolioName: t.name) { notifTarget = nil }
                .environmentObject(storageService)
        }
        .dsAlert(Binding(get: { importAlert != nil }, set: { if !$0 { importAlert = nil } }),
                 title: "Import", message: importAlert ?? "", confirmTitle: "OK", cancelTitle: nil)
        .background(keyboardShortcuts)
    }

    /// Invisible buttons that give the window native keyboard shortcuts:
    /// ⌘1 Home · ⌘2 Watchlist · ⌘3 Portfolios · ⌘4 Settings · ⌘R Refresh · ⌘N New portfolio.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { selection = .home }.keyboardShortcut("1", modifiers: .command)
            Button("") { selection = .watchlist }.keyboardShortcut("2", modifiers: .command)
            Button("") { selection = .portfoliosAll }.keyboardShortcut("3", modifiers: .command)
            Button("") { selection = .settings }.keyboardShortcut("4", modifiers: .command)
            Button("") {
                Task { await stockService.refreshAll(storageService: storageService) }
            }.keyboardShortcut("r", modifiers: .command)
            Button("") { showNewPortfolio = true }.keyboardShortcut("n", modifiers: .command)
            // ⌘W closes just this window — StockDock keeps living in the menu bar.
            Button("") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Top-right support icons, in the traffic-light clearance band (lights
            // sit on the left, so these stay clear of them).
            HStack(spacing: 6) {
                Spacer()
                SupportButton(icon: "star", title: "Star", hoverTint: DS.gold,
                              url: "https://github.com/simonsruggi/StockDock", compact: true)
                SupportButton(icon: "heart", title: "Sponsor", hoverTint: Color(red: 0.86, green: 0.30, blue: 0.46),
                              url: "https://github.com/sponsors/simonsruggi", compact: true)
            }
            .padding(.top, 12).padding(.trailing, 12).padding(.bottom, 2)
            brand
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    NavRow(icon: "newspaper", title: "Home", helpText: "Financial news for your symbols  ⌘1",
                           selected: selection == .home, namespace: navNamespace) { selection = .home }
                    NavRow(icon: "list.bullet", title: "Watchlist", helpText: "Your tracked symbols  ⌘2",
                           selected: selection == .watchlist, namespace: navNamespace) { selection = .watchlist }

                    portfoliosHeader
                    NavRow(icon: "square.grid.2x2", title: "All Portfolios",
                           trailing: trailingPercent(for: storageService.portfolios),
                           trailingTint: DS.pnlColor(aggregatePnlPercent(for: storageService.portfolios)),
                           helpText: "Combined view of every portfolio  ⌘3",
                           selected: selection == .portfoliosAll, namespace: navNamespace) { selection = .portfoliosAll }
                    ForEach(storageService.portfolios) { portfolio in
                        NavRow(icon: "briefcase", title: portfolio.name,
                               trailing: trailingPercent(for: [portfolio]),
                               trailingTint: DS.pnlColor(aggregatePnlPercent(for: [portfolio])),
                               helpText: "Open “\(portfolio.name)” · right-click for rename, notifications, export",
                               selected: selection == .portfolio(portfolio.id), namespace: navNamespace) {
                            selection = .portfolio(portfolio.id)
                        }
                        .contextMenu {
                            Button { addHoldingPortfolioId = portfolio.id } label: {
                                Label("Add Holding…", systemImage: "plus")
                            }
                            Button { renameTarget = PortfolioRef(id: portfolio.id, name: portfolio.name) } label: {
                                Label("Rename…", systemImage: "pencil")
                            }
                            Button { notifTarget = PortfolioRef(id: portfolio.id, name: portfolio.name) } label: {
                                Label("Notifications…", systemImage: "bell")
                            }
                            Button { exportPortfolios([portfolio]) } label: {
                                Label("Export…", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) {
                                storageService.deletePortfolio(id: portfolio.id)
                                if selection == .portfolio(portfolio.id) { selection = .portfoliosAll }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }

                }
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 12)
            }
            // Pinned bottom block: Settings, then the total footer.
            NavRow(icon: "gearshape", title: "Settings", helpText: "Preferences (shared with the menu bar)  ⌘4",
                   selected: selection == .settings, namespace: navNamespace) { selection = .settings }
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 6)
            TotalFooter(value: aggregateValue(for: storageService.portfolios),
                        cost: aggregateCost(for: storageService.portfolios),
                        currency: storageService.preferredCurrency,
                        decimals: storageService.amountDecimals)
            quitRow
        }
        .background(DS.sidebarBG)
        .overlay(alignment: .trailing) { DS.hairline.frame(width: 1) }
    }


    /// Explicit exit: closing the window keeps StockDock in the menu bar, so a
    /// separate "Quit" affordance makes "leave everything" discoverable.
    @State private var quitHover = false
    private var quitRow: some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.hairline)
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power").font(.system(size: 11, weight: .medium))
                    Text("Quit StockDock").font(.inter(11.5, weight: .medium, relativeTo: .caption))
                    Spacer()
                    Text("⌘Q").font(.inter(10, relativeTo: .caption2)).foregroundStyle(DS.inkTertiary)
                }
                .foregroundStyle(quitHover ? DS.down : DS.inkSecondary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .contentShape(Rectangle())
                .background(quitHover ? DS.down.opacity(0.08) : .clear)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: .command)
            .onHover { quitHover = $0 }
            .help("Quit StockDock completely — closing the window keeps it in the menu bar")
        }
    }

    /// "PORTFOLIOS" label with the quiet + button (replaces the old toolbar menu).
    private var portfoliosHeader: some View {
        HStack {
            Text("Portfolios")
                .font(DS.label)
                .foregroundStyle(DS.inkTertiary)
                .tracking(0.8).textCase(.uppercase)
            Spacer()
            DSMenu(width: 230, sections: plusMenuSections) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.inkSecondary)
                    .frame(width: 20, height: 20)
            }
            .help("New portfolio, add holding, import or export…")
        }
        .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 4)
    }

    /// Sections for the sidebar "+" DSMenu (submenu flattened to inline rows).
    private var plusMenuSections: [[DSMenuAction]] {
        var s: [[DSMenuAction]] = [[ DSMenuAction(title: "New Portfolio…", icon: "folder.badge.plus") { showNewPortfolio = true } ]]
        if !storageService.portfolios.isEmpty {
            s.append(storageService.portfolios.map { p in
                DSMenuAction(title: "Add to \(p.name)", icon: "plus") { addHoldingPortfolioId = p.id }
            })
        }
        var io = [ DSMenuAction(title: "Import Portfolios…", icon: "square.and.arrow.down") { importPortfolios() } ]
        if !storageService.portfolios.isEmpty {
            io.append(DSMenuAction(title: "Export All…", icon: "square.and.arrow.up") { exportPortfolios(storageService.portfolios) })
        }
        s.append(io)
        return s
    }

    private var brand: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("StockDock").font(.inter(15, weight: .bold, relativeTo: .headline)).foregroundStyle(DS.ink)
                Text(appVersion).font(DS.micro).foregroundStyle(DS.inkTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let dev = Bundle.main.infoDictionary?["SUFeedURL"] == nil ? " · DEV" : ""
        return "v\(v)\(dev)"
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .home:
            HomeWideView()
        case .watchlist:
            WatchlistWideView(showSearch: $showSearch)
        case .settings:
            SettingsWideView()
        case .portfoliosAll:
            NavigationStack { PortfolioOverview(scope: .all) }
        case .portfolio(let id):
            NavigationStack { PortfolioOverview(scope: .portfolio(id)) }
        }
    }

    private var newPortfolioSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Portfolio").font(.inter(15, weight: .bold, relativeTo: .headline))
            TextField("Portfolio name", text: $newPortfolioName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createPortfolio)
            HStack {
                Spacer()
                Button("Cancel") { showNewPortfolio = false; newPortfolioName = "" }
                Button("Create", action: createPortfolio)
                    .buttonStyle(.borderedProminent)
                    .tint(DS.brand)
                    .disabled(newPortfolioName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private func createPortfolio() {
        let name = newPortfolioName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        storageService.addPortfolio(name: name)
        newPortfolioName = ""
        showNewPortfolio = false
    }

    // MARK: - Import / Export (reuses StorageService JSON logic)

    private func exportPortfolios(_ portfolios: [Portfolio]) {
        guard let data = storageService.exportPortfolios(portfolios) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = (portfolios.count == 1 ? portfolios[0].name : "StockDock Portfolios") + ".json"
        panel.title = "Export Portfolios"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importPortfolios() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import Portfolios"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url) else {
                Task { @MainActor in importAlert = "Could not read file." }; return
            }
            Task { @MainActor in
                guard let imported = storageService.importPortfolios(from: data) else {
                    importAlert = "Invalid file format."; return
                }
                guard !imported.isEmpty else { importAlert = "No portfolios found in file."; return }
                storageService.mergeImportedPortfolios(imported)
                importAlert = "Imported \(imported.count) portfolio\(imported.count == 1 ? "" : "s")."
            }
        }
    }

    // MARK: - Aggregation helpers (reuse the shared valuation math)

    private func valued(_ portfolios: [Portfolio]) -> [PortfolioValuation.Input] {
        portfolios.flatMap { $0.holdings }.compactMap { holding in
            guard let quote = stockService.quotes[holding.symbol] else { return nil }
            return PortfolioValuation.Input(
                holding: holding,
                price: quote.displayPrice(extendedHours: storageService.showExtendedHours),
                rate: stockService.rate(from: quote.currency),
                costRate: stockService.rate(from: quote.currency, for: holding.purchaseDate)
            )
        }
    }

    private func aggregateValue(for portfolios: [Portfolio]) -> Double {
        PortfolioValuation.totals(valued(portfolios)).value
    }
    private func aggregateCost(for portfolios: [Portfolio]) -> Double {
        PortfolioValuation.totals(valued(portfolios)).cost
    }
    private func aggregatePnlPercent(for portfolios: [Portfolio]) -> Double {
        let t = PortfolioValuation.totals(valued(portfolios))
        return abs(t.cost) >= 0.01 ? ((t.value - t.cost) / abs(t.cost)) * 100 : 0
    }

    /// Sidebar trailing figure — nil (hidden) until at least one holding is
    /// priced, so an unpriced portfolio never shows a fake "+0.0%".
    private func trailingPercent(for portfolios: [Portfolio]) -> String? {
        guard !valued(portfolios).isEmpty else { return nil }
        return String(format: "%+.1f%%", aggregatePnlPercent(for: portfolios))
    }
}

// MARK: - Sidebar pieces

/// A subtle support button (Star / Sponsor) that opens a URL and warms to a tint
/// on hover.
private struct SupportButton: View {
    let icon: String
    let title: String
    let hoverTint: Color
    let url: String
    var compact: Bool = false
    @State private var hover = false

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Group {
                if compact {
                    Image(systemName: hover ? "\(icon).fill" : icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(hover ? hoverTint.opacity(0.14) : DS.cardAlt))
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: hover ? "\(icon).fill" : icon).font(.system(size: 11, weight: .medium))
                        Text(LocalizedStringKey(title)).font(.inter(11, weight: .medium, relativeTo: .caption))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hover ? hoverTint.opacity(0.10) : DS.cardAlt))
                }
            }
            .foregroundStyle(hover ? hoverTint : DS.inkSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(title == "Star" ? "Star the repo on GitHub" : "Sponsor development")
    }
}

private struct TotalFooter: View {
    let value: Double
    let cost: Double
    let currency: String
    var decimals: Int = 2

    var body: some View {
        let symbol = StorageService.currencySymbol(for: currency)
        let pnl = value - cost
        // Same convention as the popover: amount and percentage, always together.
        let pct: Double? = abs(cost) >= 0.01 ? (pnl / abs(cost)) * 100 : nil
        VStack(alignment: .leading, spacing: 3) {
            Divider().overlay(DS.hairline)
            SectionLabel("Total portfolio").padding(.top, 10)
            Text(StorageService.formatAmount(value, symbol: symbol, decimals: decimals))
                .font(.inter(17, weight: .bold, relativeTo: .title3).monospacedDigit())
                .foregroundStyle(DS.ink)
                .contentTransition(.numericText())
            HStack(spacing: 5) {
                Image(systemName: pnl >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8, weight: .bold))
                Text(StorageService.formatAmount(pnl, symbol: symbol, decimals: decimals, signed: true)
                     + (pct.map { String(format: " (%+.1f%%)", $0) } ?? ""))
                    .font(.inter(11, weight: .medium, relativeTo: .caption).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(DS.pnlColor(pnl))
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}
