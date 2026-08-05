# StockDock

macOS menu bar app showing live stock quotes and portfolio P&L. No account, no API key: data comes straight from Yahoo Finance.

## Description

StockDock is a lightweight app that lives in the macOS menu bar. Clicking the icon opens a popover with the watchlist, portfolios and settings. Prices update in real time over WebSocket (~1 update/sec per symbol).

## Tech stack

- **Language**: Swift 5.9
- **UI**: SwiftUI
- **Platform**: macOS 14+ (Sonoma)
- **Build system**: Swift Package Manager (`Package.swift`)
- **Real-time data**: Yahoo Finance WebSocket (`wss://streamer.finance.yahoo.com`) over protobuf
- **Fallback data**: Yahoo Finance REST API (v7 batch quotes + v8 chart)
- **Dependencies**: [apple/swift-protobuf](https://github.com/apple/swift-protobuf) (decodes WSS messages)

## Main folder structure

```
StockDock/
├── Package.swift               # SPM config, single target, macOS 14+
├── StockDock/
│   ├── StockDockApp.swift      # Entry point (@main), wires up AppDelegate
│   ├── AppDelegate.swift       # NSStatusItem, popover, 5s refresh timer
│   ├── Models/
│   │   ├── StockQuote.swift    # Models: StockQuote (with 52w range), Portfolio, Holding, SearchResult
│   │   ├── PriceAlert.swift    # PriceAlert, AlertCondition, AlertEvaluator (pure, testable logic)
│   │   ├── PortfolioNotification.swift # PortfolioNotification(Mode) + PortfolioAlertEvaluator (pure, testable logic)
│   │   └── NewsArticle.swift   # News model (decoded from the Yahoo search endpoint, no API key) for the Home tab
│   ├── Services/
│   │   ├── StockService.swift      # Fetches quotes and exchange rates from the Yahoo Finance REST API
│   │   ├── WebSocketService.swift  # Real-time streaming over WSS + protobuf + auto-reconnect
│   │   ├── NotificationManager.swift # Local notifications (UN) + webhook forwarding + AlertMonitor
│   │   ├── PortfolioMonitor.swift  # Evaluates per-portfolio notifications and fires them
│   │   ├── WebhookNotifier.swift   # POSTs to Discord/Slack webhooks (auto-detect, https + host allowlist)
│   │   ├── yaticker.pb.swift       # Swift code generated from yaticker.proto
│   │   └── StorageService.swift    # Local persistence (JSON) + formatNumber/formatAmount (locale-aware thousands separator)
│   ├── Views/
│   │   ├── ContentView.swift   # Tab container (Home / Watchlist / Portfolios / Settings)
│   │   ├── HomeView.swift      # Home tab: financial news feed (thumbnail, publisher, related tickers)
│   │   ├── WatchlistView.swift # Ticker list with prices, daily change and the 52w range bar
│   │   ├── RangeBar.swift      # 52-week bar with a position marker
│   │   ├── PortfolioListView.swift # Portfolios with per-holding P&L
│   │   ├── AddHoldingView.swift# Add/edit holding form
│   │   ├── AlertEditView.swift # Price alert creation sheet
│   │   ├── PortfolioNotificationsView.swift # Popover managing per-portfolio notifications
│   │   ├── SearchView.swift    # Ticker search by symbol or name
│   │   └── SettingsView.swift  # Currency, extended hours, menu bar, Notifications (webhook + price alert + portfolio), Sponsor section
│   ├── Assets.xcassets
│   └── Resources/AppIcon.icns
└── screenshots/                # Screenshots for the README
```

## Key features

- **Home — financial news** (main tab): news feed from the same public Yahoo endpoints (`v1/finance/search?newsCount=…`, no API key). Personalised on the symbols you follow (watchlist + holdings, up to 6 concurrent queries via `withTaskGroup`), deduplicated by `uuid`, newest first (capped at 40); falls back to "stock market" if you follow nothing. Each row: thumbnail (`AsyncImage`), title, publisher · relative time (localised), related tickers; tap → opens the article in the browser (`NSWorkspace`). Throttled refresh (max once every 5 min) plus a forced one from the header refresh button while on Home. State lives in `StockService` (`news`, `isLoadingNews`, `refreshNews`), model `NewsArticle` with decoding tests
- **Support**: Settings → "Enjoying StockDock?" section with a pink "Become a Sponsor" button → `github.com/sponsors/simonsruggi`. The README carries both funding links (GitHub Sponsors + Buy Me a Coffee) as badges, in the nav and in the dedicated section. The message stays the same: the app is free and open source forever
- **Configurable menu bar**: absolute P&L, P&L %, P&L + %, total portfolio value, best/worst watchlist symbol, portfolio recap, daily P&L, **Ticker (cycles the watchlist)**, **Ticker + Portfolio (cycles the watchlist plus one portfolio recap slide)**, icon only
- **Custom gain/loss colours (global)** (since 1.9.4): Settings → "Colors" section, gain/loss colour pickers that apply to **the whole app**, not just the menu bar. Implementation: `DS.up`/`DS.down` (and `upSoft`/`downSoft`/`pnlColor`) in `DesignSystem.swift` are **computed `@MainActor`** properties reading the custom colours from `StorageService.shared` (hex → `Color(nsColor:)`), **falling back to the defaults** `upDefault`/`downDefault` (emerald/terracotta) when the hex is empty; views showing P&L observe `StorageService`, so changing a colour re-renders them. The colour pickers are **always visible**. The **"Use system color in the menu bar"** toggle (`menuBarUseSystemColor`) affects **the bar only** (readability on any background; direction is carried by `+/−` and `▲▼`) and leaves in-app colours alone; used in `AppDelegate.updateMenuBarTitle`. Persisted as hex in `data.json`; helper `ColorHex.swift` (hex↔`NSColor`/`Color` bridge)
- **Decimal places**: Settings control for percentages (0–4) and values (Auto or 0–4), applied everywhere a number appears (menu bar, watchlist, portfolios)
- **Ticker: name vs symbol** (issue #8.2): "Show name instead of symbol" toggle (off by default) in the Ticker modes → the bar shows the readable name (e.g. "S&P 500") instead of the raw symbol ("^GSPC"). Implemented in `AppDelegate.watchlistSlide(...)`, falling back to the symbol when the name is empty; `tickerShowName` setting in `StorageService`
- **Custom symbol names** (issue #12, since 1.9.12): right-click a watchlist symbol → "Rename…" gives it a display name of your choosing, for tickers that read badly in the menu bar (`CAD/USD` → `CAD`, `^GSPC` → `S&P`). Stored in `symbolAlias: [symbol: String]` in `data.json`; read through `StorageService.displayLabel(for:fallback:)`, which wins over both the raw ticker and the Yahoo company name — it was chosen precisely because neither reads well. The real ticker is never hidden: it moves to the secondary line in the compact list and prefixes the Name column in the window. Saving an empty field clears the alias (`setAlias` removes the entry rather than storing ""), so "no alias" has a single code path. Covered by `Tests/SymbolAliasTests.swift`
- **Ticker: ordering** (issue #8.1): "Ticker order" picker (As added / By type / Alphabetical) deciding the order watchlist entries cycle **in the menu bar** (the popover already sorts by column). Pure helper `StorageService.tickerOrder(_:mode:types:)` — the "type" grouping goes stocks → ETFs → indices → futures (stable within a group, unknown types last); `watchlistSort` setting
- **No currency symbol on indices** (issue #8.3): indices have no currency, so their value isn't prefixed with a currency symbol. Detected via `StorageService.isIndex(symbol:type:)` (Yahoo `INDEX` type, falling back to the `^` convention). The asset class comes from the API (`quoteType` v7, `instrumentType` v8 chart, `SearchResult.type` in search) and is cached/persisted in `symbolType: [symbol: String]` in `data.json` — resolved once because it's stable per symbol, not recomputed on every tick
- **Localisation (6 languages)**: Settings → "Language" picker (English by default) with English, German, French, Spanish, Italian, Portuguese. Strings in `Resources/<lang>.lproj/Localizable.strings`; the in-app locale override goes through `\.environment(\.locale, …)` reactively on `ContentView` (NOT the system locale). the release script copies the `.lproj` folders into `Contents/Resources` (Bundle.main) so SwiftUI resolves them; `Package.swift` sets `defaultLocalization: "en"`. ⚠️ Under `swift run` (dev) SPM resources end up in `Bundle.module`, so translations only show in the **bundled** app
- **Watchlist**: add symbols by ticker, name or ISIN with live search; prices in their original currency or converted; PRE/POST badges for extended hours; local filter by name, symbol or ISIN
- **Multiple portfolios**: average cost basis, purchase date for the historical exchange rate, per-holding and total P&L
- **Portfolios excluded from the total** (issue #14, since 1.9.12): right-click a portfolio → "Count in Total" (a checked toggle) keeps it out of every combined figure — a paper/fantasy portfolio you want to track without it moving your net worth. `Portfolio.excludedFromTotal: Bool?` is optional so portfolios saved before 1.9.12 decode as counted. The filter lives in **exactly one place**, `StorageService.countedPortfolios`, consumed by the menu bar, "All Portfolios", the window's footer total and the cross-portfolio average buy price — the aggregation used to be open-coded in five files, and the menu bar disagreeing with the window about the total is precisely the bug that split would produce. An excluded portfolio stays whole: own chart, snapshots, notifications, export, and it renders in full colour when opened directly. In the lists it's dimmed and its figure loses the gain/loss tint (`NavRow(dimmed:)`), so "not counted" reads without adding a third colour to the design language. Covered by `Tests/ExcludedPortfolioTests.swift`
- **Shorts & leverage (issue #9)**: **Settings → Advanced → "Enable short positions & leverage"** toggle (OFF by default, `advancedPositions` in `data.json`). With it on, the add/edit holding forms (including the "Add to Portfolio" quick sheet from the watchlist context menu) show a **[ Long | Short ] picker** (quantity stays positive, the picker carries the sign) and a per-holding **leverage** field. When editing with Advanced OFF, existing direction/leverage are preserved (a normal edit never silently unwinds a short or its leverage). The maths lives on `Holding`: `pnl`/`marketValue` × `effectiveLeverage`, `pnlPercent` flips sign for shorts (price down = gain) and leverage cancels out in the position percentage (it's exposure-relative); `costBasisLocal` is the signed, leveraged cost basis, used everywhere for totals and for the portfolio-level percentage (`abs(costBasis)`, so long/short baskets don't cancel each other out). **SHORT** (orange) and **Nx** leverage (blue) badges on the holding row. `leverage: Double?` is optional → `data.json` files from before 1.7.1 decode cleanly as 1×. Covered by `Tests/ShortLeverageTests.swift` (8 cases: long/short × profit/loss × leverage)
- **Currency conversion**: supports EUR, USD, GBP, CHF, JPY, CAD, AUD; live and historical exchange rates
- **52-week range**: a watchlist bar showing where the price sits between the yearly low and high; data comes from the same quote calls (v7 with a v8 fallback) and survives WSS ticks
- **Price alerts (one-shot)**: 6 conditions (price above/below a threshold, daily change % up/down, near the 52w high/low); created from the watchlist context menu, managed in Settings (re-arm, delete, "triggered" badge, **"Clear all"** with confirmation); local macOS notification via `UNUserNotificationCenter`; evaluated on every price update (WSS tick, REST, launch, wake); fire once, then disarm
- **Add to Portfolio from the watchlist**: right-click a symbol → "Add to Portfolio" → pick a portfolio → `QuickAddHoldingView` quick sheet (price pre-filled with the current one); with Advanced ON it includes the Long/Short picker and leverage, like the main sheet
- **Customisable watchlist display**: Settings toggles to show/hide the company name, day range, 52w bar and absolute change on each row; all on by default, persisted in `data.json`
- **Discord/Slack notifications**: Settings toggle + webhook URL + "Send test"; every notification (price alert and portfolio) is forwarded to the webhook alongside the macOS notification; auto-detects Discord (green/red coloured embed) vs Slack (plain text); https only, on known hosts (SSRF-safe); works in dev too
- **Per-portfolio notifications**: right-click a portfolio header → "Notifications…"; also managed in Settings with **"Clear all"** (clears every portfolio's rules, with confirmation); 4 modes (daily change ≥ %, ≥ amount, daily summary, value milestone); defaults ±1% / ±250 / milestone every 10,000 / summary after 22:00. **Anti-spam**: the *daily move* modes (`dailyPercent`/`dailyAbsolute`) fire **once per direction per day** — on the first crossing of +threshold and the first of −threshold, then silence until the next day (`crossingStep` returns ±1 and the per-direction `lastStepUp`/`lastStepDown` markers are scoped to `lastDay`); built this way to kill the step spam (it used to notify at +1%, +2%, +3%… on a trending day). Milestones are silently "primed" on the first pass and then only fire on a new high/low; on top of that a backstop in `NotificationManager.send` prevents the *same* identifier from firing again within 120s (no notification type can spam at tick rate). The day's change is `change` per share × quantity × FX in the preferred currency; evaluated on every price update; rules and state persisted per portfolio id in `data.json`. Daily-change notifications and the summary include a **per-symbol breakdown** (symbol · change % · value, aggregated by symbol, sorted by the day's impact, capped at 12 rows + "…and N more") so you can see what actually moved the portfolio
- **Extended hours**: pre-market and after-hours prices with their own P&L
- **Chart range is remembered** (issue #14, since 1.9.12): the range picker used to snap back to a hard-coded default on every open (1M for the symbol chart, All for the portfolio chart). It now restores the last range picked, kept separately per chart kind in `lastSymbolChartRange` / `lastPortfolioChartRange` — which serves the "default to 24h" request without imposing 24h on everyone, and without adding a setting
- **Persistence**: data saved in `~/Library/Application Support/StockDock/data.json` (watchlist, portfolios, isinMap, aliases, alerts, portfolio notifications, webhook, preferences); nothing is sent to external servers
- **Tests**: `StockDockTests` target (`Tests/`) with unit tests over the pure logic — `AlertEvaluator` (every condition plus edge cases), `PortfolioAlertEvaluator` (crossingStep/milestone/summary), `fiftyTwoWeekPosition`, number formatting, `TickerOrderingTests` (issue #8: `isIndex` + `tickerOrder`), `ShortLeverageTests` (issue #9: P&L/marketValue/pnlPercent/costBasis over shorts + leverage), `SymbolAliasTests` and `ExcludedPortfolioTests` (issues #12 and #14). Run with `swift test`
- **Portfolio export/import**: export one or all portfolios to JSON via NSSavePanel; import via NSOpenPanel with name dedup and regenerated UUIDs
- **Reactive menu bar**: updates immediately on any portfolio change, settings change or popover close (on top of WebSocket ticks and REST polling)
- **Debounced saves**: disk writes are debounced by 100ms so they never block the main thread; an immediate save on quit; no redundant save during the initial load
- **Reactive subscriptions**: a Combine observer on `$portfolios` + `$watchlist` (500ms debounce) automatically updates the WebSocket subscriptions and triggers `refreshAll` after any mutation

## Desktop window (full app) — new in 1.9.0

Alongside the menu bar popover, StockDock has a **real desktop window** (1220×820, min 1000×680), opened from the **"Open"** button (emerald capsule) in the popover header, or from `AppDelegate.showPortfolioWindow()`. It's the app in expanded form: **the same tabs as the popover** (Home / Watchlist / Portfolios / Settings), **the same data and the same preferences** over the same `data.json` (shared `StockService`/`StorageService`) — a change in one place shows up instantly in the other and in the menu bar. It coexists with the popover: opening switches to `activationPolicy .regular` (Dock icon), closing returns to `.accessory`.

- **"Private banking" design system** (`Views/DesignSystem.swift`): warm paper palette with restrained emerald, `premiumCard(elevated:)` (three elevation levels), Inter type scale (`DS.display/titleXL/figure/…`), shared components `PageScaffold`/`PageHeader`/`ScrollEdgeFade`/`Card`/`StatTile`/`ChangePill`/`Tag`/`BrandMark`/`NavRow` (sliding selection pill via `matchedGeometryEffect`)/`SegmentedRangePicker`/`RefreshButton`. Appearance follows the user's Theme preference (System / Light / Dark, issue #11). Every tab uses the same `PageScaffold` → identical title, column (max 1120), gutter and background (cross-tab consistency).
- **Chrome**: transparent titlebar + `titleVisibility .hidden` + `fullSizeContentView`; no system toolbar (the "+" for a new portfolio/holding lives in the sidebar's "PORTFOLIOS" header); `isMovableByWindowBackground`.
- **Shortcuts**: ⌘1 Home · ⌘2 Watchlist · ⌘3 Portfolios · ⌘4 Settings · ⌘R Refresh · ⌘N New portfolio (invisible buttons in `PortfolioWindowView`).
- **Overview** (`PortfolioOverview.swift`): full-bleed hero with the value chart as the card's background + `SegmentedRangePicker` + `contentTransition(.numericText())`; stat tiles; **Allocation** (donut with asset count + legend + per-type diversification strip, hovering highlights the sector); **movers** with a gauge; **positions** with a weight bar, the share count next to the company name, and hover. The value chart uses **real snapshots** when there are ≥2 days, otherwise an **"ESTIMATED" backfill** (dashed grey line) reconstructed from price history × current positions (`Models/PortfolioBackfill.swift`, pure + tested). The estimated curve **starts at the oldest purchase** and each position enters from **its own** `purchaseDate` (holdings with no date are valued across the whole window): without this, "All" projected today's quantities back to the earliest quote Yahoo happened to have and drew a 2026 portfolio starting in 2005. Consequently "All" uses the **daily 2y** series when the oldest purchase fits inside it (the monthly `range=max` only for genuinely older portfolios), and the X-axis label follows the **drawn span** — `6 lug` under a year, four-digit `gen 2005` above (`gen 05` read as the 5th of January).
- **Real price charts** (`Views/PriceChartCard.swift`, `Models/PriceHistory.swift`): Yahoo v8 history (1 year daily, 1h cache) + 5m intraday for **24H** (5min cache); 24H/7D/1M/1Y/All range picker, tint following the period's direction, endpoint dot, gridlines on both axes and a hover crosshair with tooltip. Used in the **holding detail** (`HoldingDetailView.swift`, with the 52-week bar, a "you bought here" tick, Position facts, **Related news** and an alert button) and in the **symbol sheet** (double-click a watchlist row → `SymbolDetailSheet.swift`).
- **Wide watchlist** (`WatchlistWideView.swift`): custom sortable list (clickable headers) inside a card. Columns **Symbol / Name / Price / After hrs / Trend 1M / 52-week**. Each price is paired with **its own** % in the same cell on the same baseline (Price → the day's move vs the previous close; After hrs → the pre/post move vs the regular close), so price and % always agree — no more detached "Change" pill. **Session-aware hierarchy** (`extendedSession`): during pre/post-market the After hrs column takes precedence (ink price + coloured `ChangePill`) and Price drops to context (grey); during regular hours it's the reverse. Headers **sort by the % you see** — Price by the day's %, After hrs by the pre/post move (never by the raw extended price), via the pure helper `StorageService.sortedByExtendedPercent(_:ascending:percent:)`, with rows lacking extended data always last. The After hrs column (and its sort) respects the **Show extended hours** setting: OFF ⇒ column hidden, only regular-market values remain. **Sparklines in a single batched request** (`ensureSparklines`, Yahoo multi-symbol `spark` endpoint). Double-click or right-click → "View Chart".
- **Wide Home** (`HomeWideView.swift`): news card with a full-width **Featured** lead + grid; **wide Settings** (`SettingsWideView.swift`): native two-column cards (not the system Form), emerald tint.
- **Localisation**: the window's strings live in the 6 `Localizable.strings` files (92 keys added in 1.9.0) alongside the popover's.
- **Dev affordance**: `SD_OPEN_WINDOW=1` opens the window at launch, `SD_OPEN_TAB=home|watchlist|settings` preselects a tab (for deterministic screenshots).

## Building and running

### From source with Swift PM

```bash
git clone https://github.com/simonsruggi/StockDock.git
cd StockDock
swift build -c release
# Executable: .build/release/StockDock
```

### Build as an app bundle (Xcode)

```bash
xcodebuild -scheme StockDock -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode build
```

### Quick start (development)

```bash
swift run
```

The app doesn't appear in the Dock (`.accessory` policy): the icon shows up in the menu bar, top right.

## Data architecture

- **WebSocket (primary)**: `WebSocketService` connects to `wss://streamer.finance.yahoo.com/?version=2` and receives ticks as JSON-wrapped base64 protobuf. Ticks are buffered and flushed in batches once a second to avoid excessive SwiftUI redraws.
- **REST polling (secondary/supervisor)**: refreshes quotes + exchange rates (current and historical) every 60s. Used as the initial bootstrap, as a fallback when the WSS drops, and as a **supervisor**: each cycle calls `WebSocketService.ensureConnected(...)`, which revives a dead socket within one cycle instead of leaving it stuck until a manual restart.
- **Cache eviction**: on every REST refresh, quotes, exchange rates and historical rates that are no longer needed get dropped.
- **Sleep/Wake**: the WSS disconnects on system sleep and reconnects on wake with an immediate refresh.
- **P&L with correct FX**: P&L is computed as `marketValue × currentRate − costBasis × historicalRate`, using the exchange rate as of the purchase date for the cost basis.
- **Resilient auto-reconnect**: exponential backoff (2s, 4s, 8s… capped at 120s). The pure, testable recovery logic is isolated in `ConnectionSupervisor` (`refreshIsBlocking`, `shouldReconnect`). Additional defences: `didCompleteWithError` (catches failures before the socket opens), a connection watchdog (12s), identity guards on the delegates (no double reconnect), and a self-healing timestamped refresh flag (never wedged again after a sleep/wake race). Covered by `Tests/ConnectionSupervisorTests`.
- **applyTick (WSS)**: a tick updates the *regular* price only during the REGULAR session; PRE/POST ticks go to their own fields, so with extended hours OFF you always see the last regular close (`Tests/ApplyTickTests`).

## Important notes

- **No API key required**: Yahoo Finance needs no authentication, but does use a cookie+crumb mechanism, handled automatically by `StockService`
- **API fallback**: if the v7 batch quote fails, the v8 chart API is used for each symbol individually
- **Protobuf**: the `yaticker.proto` schema in the root generates `yaticker.pb.swift` via `protoc --swift_out`. Regenerate if the schema changes: `protoc --swift_out=StockDock/Services/ yaticker.proto`
- **Requirements**: Xcode 15+ and macOS 14 Sonoma or later
- **Signing/entitlements**: `StockDock.entitlements` sits in the root for network access
- **CPU cost (rule)**: publishing a tick invalidates *every* view observing `StockService` (it's an `ObservableObject`, so granularity is the whole object), which means each flush costs a full layout + rasterization pass over the open window (~300ms of CPU with the Portfolio window up). Hence two rules: (1) any price-driven animation must finish **within** the flush interval — use `DS.tick`, never a spring with `response` ≥ 0.4, otherwise SwiftUI interpolates non-stop and re-rasterizes shadow blurs on the CPU; (2) the flush rate adapts to focus (`tickFlushActive` / `tickFlushBackground` in `AppDelegate`). Profile with `/usr/bin/sample <pid>`: continuous `RBInterpolatedDisplayListContents` means an animation that never settles. Structural fix still open: migrate `StockService` to `@Observable` so only the views reading the changed quote are invalidated.
- **Release / What's New**: releases are cut by a local script (not in the repo — it needs the Developer ID, the notarization profile and the Sparkle private key, so it's of no use to anyone else). It bumps `Info.plist`, builds Release, code-signs, notarizes and staples, EdDSA-signs for Sparkle, updates `appcast.xml`, cuts the GitHub release and updates the Homebrew cask. The "What's New" notes Sparkle shows are written to `release-notes/<version>.html` (HTML) and injected into the appcast's `<description>`

## TODO / ideas

- **DMG for manual download**: add a step to the release script generating a notarized `.dmg` (drag-to-Applications window, preferably via `create-dmg`) and attach it as an extra asset on the GitHub Release, for non-technical users. Sparkle keeps using the `.zip` for auto-updates (the appcast is unchanged); the DMG must be signed + notarized + stapled separately, otherwise Gatekeeper blocks it. The README/site "Download" link would point at the DMG.
- **Chart reference lines** (issue #14.2, pending clarification): a fixed line for the previous close on the intraday chart, or the average buy price on a position. Gridlines and the hover crosshair already exist.
