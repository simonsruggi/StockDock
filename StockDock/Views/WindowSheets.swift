import SwiftUI

// Desktop-window input sheets, styled in the "private banking" design system
// (Inter, emerald, cards) so they match the window instead of the small popover
// forms. They reuse the SAME StorageService/StockService logic — only the
// presentation is new. The compact popover versions stay for the menu bar.

/// A DS-styled text field with its own emerald focus ring.
struct DSTextField: View {
    var placeholder: String
    @Binding var text: String
    var mono: Bool = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(mono ? DS.figure : DS.body)
            .foregroundStyle(DS.ink)
            .focused($focused)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.cardAlt))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? DS.brand : DS.hairline, lineWidth: focused ? 1.5 : 1))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A DS-styled date field that opens a fully custom month calendar (no system
/// graphical picker, which clashes with the aesthetic).
struct DSDatePicker: View {
    @Binding var date: Date
    @State private var showCalendar = false

    var body: some View {
        Button { showCalendar.toggle() } label: {
            HStack(spacing: 8) {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(DS.body).foregroundStyle(DS.ink)
                Spacer()
                Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(DS.inkSecondary)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.cardAlt))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(showCalendar ? DS.brand : DS.hairline, lineWidth: showCalendar ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
            DSCalendar(date: $date) { showCalendar = false }
                .padding(14)
                .frame(width: 268)
                .background(DS.card)
        }
    }
}

/// A hand-built month calendar in the design system: emerald selection, warm
/// neutrals, Monday-first grid.
private struct DSCalendar: View {
    @Binding var date: Date
    let onPick: () -> Void

    @State private var month: Date = Date()
    private let cal = Calendar.current

    private var weekdaySymbols: [String] {
        // Monday-first ordering of the locale's very-short weekday symbols.
        let syms = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(syms[first...] + syms[..<first])
    }

    /// Day cells for the visible month, with leading blanks for alignment.
    private var cells: [Date?] {
        guard let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else { return [] }
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth) // 1=Sun…7=Sat
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            out.append(cal.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.inter(13, weight: .semibold, relativeTo: .body)).foregroundStyle(DS.ink)
                Spacer()
                stepButton("chevron.left") { shift(-1) }
                stepButton("chevron.right") { shift(1) }
            }
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s).font(DS.micro).foregroundStyle(DS.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 30) }
                }
            }
        }
        .onAppear { month = date }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.inkSecondary).frame(width: 24, height: 24)
                .background(Circle().fill(DS.cardAlt))
        }.buttonStyle(.plain)
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: date)
        let isToday = cal.isDateInToday(day)
        return Button {
            date = day
            onPick()
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.inter(12, weight: selected ? .bold : .regular, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(selected ? .white : DS.ink)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(selected ? DS.brand : .clear)
                )
                .overlay(
                    Circle().strokeBorder(isToday && !selected ? DS.brand.opacity(0.5) : .clear, lineWidth: 1)
                )
        }.buttonStyle(.plain)
    }

    private func shift(_ months: Int) {
        if let m = cal.date(byAdding: .month, value: months, to: month) { month = m }
    }
}

/// A labelled field block: uppercase DS label above a control.
struct FieldBlock<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(label)
            content
        }
    }
}

/// Shared sheet chrome: title + Cancel, DS ground, fixed width.
private struct SheetShell<Content: View>: View {
    let title: String
    let onCancel: () -> Void
    var width: CGFloat = 460
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title)).font(DS.titleXL).tracking(-0.3).foregroundStyle(DS.ink)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.inter(12, weight: .medium, relativeTo: .body))
                    .foregroundStyle(DS.inkSecondary)
                    .keyboardShortcut(.cancelAction)
            }
            content
        }
        .padding(24)
        .frame(width: width)
        .background(DS.ground)
    }
}

/// A brand-filled primary button (Add / Save / Create).
private struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.inter(13, weight: .semibold, relativeTo: .body))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(enabled ? DS.brand : DS.inkTertiary))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Holding form (add / add-symbol / edit)

/// Add or edit a holding, DS-styled and wide. One view for three flows.
struct HoldingFormSheet: View {
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var storageService: StorageService

    enum Mode {
        case add(portfolioId: UUID)
        case addSymbol(symbol: String, portfolioId: UUID)
        case edit(portfolioId: UUID, holding: Holding)
    }
    let mode: Mode
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedSymbol: String?
    @State private var quantityText = ""
    @State private var avgPriceText = ""
    @State private var leverageText = ""
    @State private var isShort = false
    @State private var purchaseDate = Date()

    private var portfolioId: UUID {
        switch mode {
        case .add(let id), .addSymbol(_, let id), .edit(let id, _): return id
        }
    }
    private var editingHolding: Holding? {
        if case .edit(_, let h) = mode { return h }
        return nil
    }
    private var isEditing: Bool { editingHolding != nil }
    private var fixedSymbol: String? {
        switch mode {
        case .addSymbol(let s, _): return s
        case .edit(_, let h): return h.symbol
        case .add: return nil
        }
    }
    private var symbol: String? { fixedSymbol ?? selectedSymbol }

    /// #24: the avg price is stored in the stock's own currency, not in the one
    /// the lists display prices in. Naming it on the field is what stops people
    /// converting the figure by hand before typing it in.
    private var avgPriceLabel: String {
        guard let sym = symbol,
              let currency = stockService.quotes[sym]?.currency,
              !currency.isEmpty
        else { return "Avg price" }
        return "Avg price (\(currency))"
    }

    private var title: String {
        if let h = editingHolding { return "Edit \(h.symbol)" }
        return "Add holding"
    }

    var body: some View {
        SheetShell(title: title, onCancel: onDismiss) {
            // Symbol
            if let sym = symbol {
                symbolChip(sym, removable: fixedSymbol == nil)
            } else {
                searchField
            }

            if storageService.advancedPositions {
                FieldBlock("Position") {
                    SegmentedRangePicker(options: [false, true],
                                         label: { $0 ? "Short" : "Long" },
                                         selection: $isShort)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                FieldBlock("Quantity") { DSTextField(placeholder: "0", text: $quantityText, mono: true) }
                FieldBlock(avgPriceLabel) { DSTextField(placeholder: "0.00", text: $avgPriceText, mono: true) }
                if storageService.advancedPositions {
                    FieldBlock("Leverage") { DSTextField(placeholder: "1×", text: $leverageText, mono: true) }
                        .frame(width: 90)
                }
            }

            FieldBlock("Purchase date") {
                DSDatePicker(date: $purchaseDate)
            }

            if let info = costBasisInfo {
                Text(info).font(DS.caption).foregroundStyle(DS.inkTertiary)
            }

            PrimaryButton(title: isEditing ? "Save" : "Add", enabled: canSave, action: save)
        }
        .onAppear(perform: prefill)
    }

    // MARK: Symbol UI

    private func symbolChip(_ sym: String, removable: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.brand.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay(Text(sym.prefix(2)).font(.inter(10, weight: .bold, relativeTo: .caption2)).foregroundStyle(DS.brand))
            Text(sym).font(.inter(14, weight: .semibold, relativeTo: .body).monospacedDigit()).foregroundStyle(DS.ink)
            if let name = stockService.quotes[sym]?.name, !name.isEmpty {
                Text(name).font(DS.caption).foregroundStyle(DS.inkTertiary).lineLimit(1)
            }
            Spacer()
            if removable {
                Button { selectedSymbol = nil; searchText = ""; searchResults = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DS.inkTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.cardAlt))
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldBlock("Symbol") {
                DSTextField(placeholder: "Symbol, name or ISIN (e.g. AAPL)", text: $searchText)
                    .onChange(of: searchText) { _, new in runSearch(new) }
            }
            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults.prefix(6)) { r in
                        Button { select(r) } label: {
                            HStack(spacing: 8) {
                                Text(r.symbol).font(DS.figure).foregroundStyle(DS.ink)
                                Text(r.name).font(DS.caption).foregroundStyle(DS.inkTertiary).lineLimit(1)
                                Spacer()
                                Text(r.exchange).font(DS.micro).foregroundStyle(DS.inkTertiary)
                            }
                            .padding(.vertical, 7).padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if r.id != searchResults.prefix(6).last?.id {
                            Divider().overlay(DS.hairline.opacity(0.6)).padding(.horizontal, 8)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.card))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline))
            }
        }
    }

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        guard q.count >= 1 else { searchResults = []; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            searchResults = await stockService.search(query: q)
        }
    }

    private func select(_ r: SearchResult) {
        searchTask?.cancel()
        selectedSymbol = r.symbol
        searchResults = []
        if let q = stockService.quotes[r.symbol] { avgPriceText = String(format: "%.2f", q.price) }
    }

    // MARK: Logic

    private var canSave: Bool {
        symbol != nil &&
        Double(quantityText.replacingOccurrences(of: ",", with: ".")).map { abs($0) > 0 } == true &&
        Double(avgPriceText.replacingOccurrences(of: ",", with: ".")).map { $0 > 0 } == true
    }

    private var costBasisInfo: String? {
        guard let sym = symbol,
              let quote = stockService.quotes[sym],
              quote.currency != storageService.preferredCurrency,
              let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: ".")),
              qty != 0, price > 0 else { return nil }
        let stockSym = StorageService.currencySymbol(for: quote.currency)
        let prefSym = StorageService.currencySymbol(for: storageService.preferredCurrency)
        let rate = stockService.rate(from: quote.currency, for: purchaseDate)
        let costStock = price * abs(qty)
        return "Cost basis: \(prefSym)\(String(format: "%.2f", costStock * rate))  (\(stockSym)\(String(format: "%.2f", costStock)) × \(String(format: "%.4f", rate)))"
    }

    private func prefill() {
        if let h = editingHolding {
            quantityText = String(format: "%.2f", abs(h.quantity))
            avgPriceText = String(format: "%.2f", h.avgPrice)
            leverageText = (h.leverage.map { $0 != 1 ? String(format: "%g", $0) : "" }) ?? ""
            isShort = h.quantity < 0
            purchaseDate = h.purchaseDate ?? Date()
        } else if let sym = fixedSymbol, let q = stockService.quotes[sym] {
            avgPriceText = String(format: "%.2f", q.price)
        }
    }

    private func save() {
        let advanced = storageService.advancedPositions
        guard let sym = symbol,
              let qty = Double(quantityText.replacingOccurrences(of: ",", with: ".")),
              let price = Double(avgPriceText.replacingOccurrences(of: ",", with: ".")),
              price > 0, abs(qty) > 0 else { return }
        // Keep existing direction/leverage on a plain edit with Advanced off.
        let short = advanced ? isShort : (editingHolding?.quantity ?? 0) < 0
        let signedQty = short ? -abs(qty) : abs(qty)
        let leverage: Double? = {
            guard advanced else { return editingHolding?.leverage }
            guard let l = Double(leverageText.replacingOccurrences(of: ",", with: ".")), l > 0, l != 1 else { return nil }
            return l
        }()
        if let h = editingHolding {
            storageService.updateHolding(in: portfolioId, holdingId: h.id, quantity: signedQty, avgPrice: price, purchaseDate: purchaseDate, leverage: leverage)
        } else {
            storageService.addHolding(to: portfolioId, symbol: sym, quantity: signedQty, avgPrice: price, purchaseDate: purchaseDate, leverage: leverage)
        }
        Task { await stockService.refreshAll(storageService: storageService) }
        onDismiss()
    }
}

// MARK: - Rename portfolio

struct RenamePortfolioSheet: View {
    @EnvironmentObject var storageService: StorageService
    let portfolioId: UUID
    let onDismiss: () -> Void
    @State private var name: String

    init(portfolioId: UUID, currentName: String, onDismiss: @escaping () -> Void) {
        self.portfolioId = portfolioId
        self.onDismiss = onDismiss
        _name = State(initialValue: currentName)
    }

    var body: some View {
        SheetShell(title: "Rename portfolio", onCancel: onDismiss, width: 380) {
            FieldBlock("Name") { DSTextField(placeholder: "Portfolio name", text: $name) }
            PrimaryButton(title: "Save", enabled: !trimmed.isEmpty, action: save)
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }
    private func save() {
        guard !trimmed.isEmpty else { return }
        storageService.renamePortfolio(id: portfolioId, name: trimmed)
        onDismiss()
    }
}

/// Issue #12: give a symbol a custom display name, for tickers that read badly in
/// the menu bar ("CAD/USD", "^GSPC"). Saving an empty field clears the alias and
/// falls back to the ticker, so there's no separate "reset" affordance to find.
struct RenameSymbolSheet: View {
    @EnvironmentObject var storageService: StorageService
    let symbol: String
    let onDismiss: () -> Void
    @State private var name: String

    init(symbol: String, currentAlias: String, onDismiss: @escaping () -> Void) {
        self.symbol = symbol
        self.onDismiss = onDismiss
        _name = State(initialValue: currentAlias)
    }

    var body: some View {
        SheetShell(title: "Rename \(symbol)", onCancel: onDismiss, width: 380) {
            FieldBlock("Display name") {
                DSTextField(placeholder: symbol, text: $name)
            }
            PrimaryButton(title: "Save", enabled: true, action: save)
        }
    }

    private func save() {
        storageService.setAlias(name, for: symbol)
        onDismiss()
    }
}

// MARK: - Portfolio notifications

/// DS-styled create/manage sheet for a portfolio's recurring notifications.
struct PortfolioNotificationsSheet: View {
    @EnvironmentObject var storageService: StorageService
    let portfolioId: UUID
    let portfolioName: String
    let onDismiss: () -> Void

    @State private var newMode: PortfolioNotificationMode = .dailyPercent
    @State private var thresholdText = ""

    private var currencySymbol: String { StorageService.currencySymbol(for: storageService.preferredCurrency) }
    private var existing: [PortfolioNotification] { storageService.notifications(for: portfolioId) }
    private var thresholdUnit: String {
        switch newMode.thresholdKind {
        case .percent: return "%"
        case .currency: return currencySymbol
        case .hour: return "h"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notifications · \(portfolioName)").font(DS.titleXL).tracking(-0.3).foregroundStyle(DS.ink)
                Spacer()
                Button("Done", action: onDismiss).buttonStyle(.plain)
                    .font(.inter(12, weight: .semibold, relativeTo: .body)).foregroundStyle(DS.brand)
                    .keyboardShortcut(.cancelAction)
            }

            if !existing.isEmpty {
                VStack(spacing: 0) {
                    ForEach(existing) { n in
                        HStack(spacing: 10) {
                            Image(systemName: n.mode.systemImage).font(.system(size: 12))
                                .foregroundStyle(n.isEnabled ? DS.brand : DS.inkTertiary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.mode.label).font(DS.bodyStrong).foregroundStyle(DS.ink)
                                Text(describe(n)).font(DS.micro).foregroundStyle(DS.inkTertiary)
                            }
                            Spacer()
                            DSToggle(isOn: Binding(
                                get: { n.isEnabled },
                                set: { storageService.setPortfolioNotificationEnabled(id: n.id, in: portfolioId, enabled: $0) }))
                            Button { storageService.removePortfolioNotification(id: n.id, from: portfolioId) } label: {
                                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(DS.inkTertiary)
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        if n.id != existing.last?.id { Divider().overlay(DS.hairline.opacity(0.6)) }
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Add notification")
                DSPicker(options: PortfolioNotificationMode.allCases.map { ($0, $0.label) },
                         selection: $newMode, width: 240)
                    .onChange(of: newMode) { prefill() }
                Text(newMode.help).font(DS.caption).foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(thresholdFieldLabel)).font(DS.caption).foregroundStyle(DS.inkSecondary)
                    DSTextField(placeholder: placeholder, text: $thresholdText, mono: true).frame(width: 110)
                    Text(thresholdUnit).font(DS.body).foregroundStyle(DS.inkSecondary)
                    Spacer()
                }
                PrimaryButton(title: "Add", enabled: (parsed ?? 0) > 0, action: add)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.cardAlt))

            if !storageService.discordEnabled {
                Text("Tip: enable the Discord/Slack webhook in Settings to also receive these on your phone.")
                    .font(DS.micro).foregroundStyle(DS.inkTertiary)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(DS.ground)
        .onAppear(perform: prefill)
    }

    private var parsed: Double? { Double(thresholdText.replacingOccurrences(of: ",", with: ".")) }
    private var thresholdFieldLabel: String {
        switch newMode.thresholdKind {
        case .percent: return "Step"
        case .currency: return newMode == .milestone ? "Every" : "Step"
        case .hour: return "After"
        }
    }
    private var placeholder: String {
        switch newMode.thresholdKind {
        case .percent: return "1"
        case .currency: return newMode == .milestone ? "10000" : "250"
        case .hour: return "22"
        }
    }
    private func prefill() {
        thresholdText = (newMode.thresholdKind == .currency || newMode.thresholdKind == .hour)
            ? String(format: "%.0f", newMode.defaultThreshold)
            : String(format: "%g", newMode.defaultThreshold)
    }
    private func add() {
        guard let v = parsed, v > 0 else { return }
        storageService.addPortfolioNotification(PortfolioNotification(mode: newMode, threshold: v), to: portfolioId)
        prefill()
    }
    private func describe(_ n: PortfolioNotification) -> String {
        switch n.mode {
        case .dailyPercent: return "Every ±\(String(format: "%g", n.threshold))% move today"
        case .dailyAbsolute: return "Every ±\(currencySymbol)\(String(format: "%g", n.threshold)) move today"
        case .milestone: return "Every \(currencySymbol)\(String(format: "%g", n.threshold)) crossed"
        case .dailySummary: return "Daily after \(String(format: "%.0f", n.threshold)):00"
        }
    }
}

// MARK: - Watchlist search

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

// MARK: - Price alert

/// DS-styled one-shot price alert creation.
struct PriceAlertSheet: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService
    let symbol: String
    let onDismiss: () -> Void

    @State private var condition: AlertCondition = .priceAbove
    @State private var thresholdText = ""

    private var quote: StockQuote? { stockService.quotes[symbol] }
    private var currencySymbol: String {
        StorageService.currencySymbol(for: quote?.currency ?? storageService.preferredCurrency)
    }
    private var thresholdUnit: String {
        condition.thresholdKind == .price ? currencySymbol : "%"
    }

    var body: some View {
        SheetShell(title: "Alert · \(symbol)", onCancel: onDismiss, width: 420) {
            FieldBlock("Condition") {
                DSPicker(options: AlertCondition.allCases.map { ($0, $0.label) },
                         selection: $condition, width: 260)
                    .onChange(of: condition) { prefill() }
            }
            FieldBlock(thresholdLabel) {
                HStack(spacing: 8) {
                    DSTextField(placeholder: placeholder, text: $thresholdText, mono: true)
                    Text(thresholdUnit).font(DS.body).foregroundStyle(DS.inkSecondary)
                }
            }
            if let q = quote {
                Text("Current price: \(currencySymbol)\(StorageService.formatNumber(q.effectivePrice, decimals: 2))")
                    .font(DS.caption).foregroundStyle(DS.inkTertiary)
            }
            PrimaryButton(title: "Create alert", enabled: parsedValue != nil, action: create)
        }
        .onAppear(perform: prefill)
    }

    private var parsedValue: Double? {
        guard let v = Double(thresholdText.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return v
    }

    private var thresholdLabel: String {
        switch condition {
        case .priceAbove, .priceBelow: return "Target price"
        case .dailyChangeUp, .dailyChangeDown: return "Daily change threshold"
        case .near52WeekHigh, .near52WeekLow: return "Proximity (within %)"
        }
    }
    private var placeholder: String { condition.thresholdKind == .price ? "0.00" : "5" }

    private func prefill() {
        switch condition.thresholdKind {
        case .price: if let q = quote { thresholdText = String(format: "%.2f", q.effectivePrice) }
        case .percent:
            switch condition {
            case .near52WeekHigh, .near52WeekLow: thresholdText = "2"
            default: thresholdText = "5"
            }
        }
    }

    private func create() {
        guard let v = parsedValue else { return }
        storageService.addAlert(PriceAlert(symbol: symbol, condition: condition, threshold: v))
        onDismiss()
    }
}
