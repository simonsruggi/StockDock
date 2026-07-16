# User Stories — StockDock

## US-01: Menu Bar Display
**As a** user, **I want** to see a summary of my portfolio in the macOS menu bar **so that** I can monitor my investments at a glance.

- [x] Menu bar shows P&L in the chosen format (absolute, %, both, total value, best/worst stock, icon only)
- [x] Values update in real time with prices
- [x] Green (positive) / red (negative) color coding, with configurable up/down colors (see US-18)
- [x] 11 display modes: P&L, P&L %, P&L + %, Total Value, Best Stock, Worst Stock, Best & Worst, Portfolio recap, Ticker (cycle watchlist), Ticker + Portfolio (cycle), Icon Only
- [x] "Ticker + Portfolio (cycle)" rotates through the watchlist AND a portfolio-recap slide in the same cycle (issue #7.3)
- [x] Numbers > 1,000 use a locale-aware thousands separator (menu bar, watchlist, portfolio, alerts, notifications)
- [x] Percentages can optionally show 2 decimals instead of 1 (Settings toggle, off by default — issue #7.4)

## US-02: Watchlist
**As a** user, **I want** to maintain a watchlist of stocks **so that** I can monitor their prices.

- [x] Search stocks by symbol, name or ISIN
- [x] Add/remove stocks from the watchlist
- [x] Current price, daily change %, extended hours prices
- [x] Each price is paired with its own % move in the same cell (Price → today's %, After hrs → pre/post %), same baseline so they always agree
- [x] Session-aware hierarchy: during pre/post-market the After-hrs price/% reads first (ink + coloured pill) and the regular price dims to context; during regular hours it's the reverse
- [x] Column headers sort by the % you see — Price sorts by today's %, After hrs by the pre/post % move (never by the raw extended price)
- [x] Local filter by symbol, name or ISIN
- [x] Auto-sort by daily performance (best on top)
- [x] PRE (orange) / POST (purple) badges for extended hours

## US-03: Portfolio Management
**As a** user, **I want** to create and manage multiple portfolios with holdings **so that** I can track my investment performance.

- [x] Create, rename, delete portfolios
- [x] Add holdings with symbol, quantity, average price and purchase date
- [x] Edit existing holdings (quantity, average price, purchase date)
- [x] Delete holdings
- [x] Total portfolio value, P&L and P&L %
- [x] Per holding: market value, P&L and P&L %
- [x] Filter portfolios by name or symbol

## US-04: Quick Add from Watchlist to Portfolio
**As a** user, **I want** to quickly add a stock from the watchlist to a portfolio **so that** I don't have to retype the symbol.

- [x] Right-click on watchlist stock → "Add to Portfolio" menu with portfolio list
- [x] Quick form for quantity, average price and purchase date (pre-fills current price)

## US-05: Real-Time Updates
**As a** user, **I want** prices to update in real time **so that** I always have up-to-date data.

- [x] Yahoo Finance WebSocket (~1 tick/sec per symbol)
- [x] Automatic reconnection with exponential backoff (2s, 4s, 8s... max 120s)
- [x] Watchdog: no ticks for 60s → reconnect
- [x] Heartbeat every 15s to keep the connection alive
- [x] REST polling every 5 min as fallback for exchange rates
- [x] After portfolio/watchlist change, WebSocket subscriptions updated within 500ms
- [x] Ticks buffered and flushed 1x/sec to avoid excessive rendering
- [x] Batch quote parsing is resilient: a single delisted/suspended ticker (returned without a price) is skipped instead of failing the whole v7 batch and dropping every symbol's live quote — pure `StockService.parseV7Response`, covered by `Tests/V7QuoteParsingTests.swift` (bugcheck 2026-07-13)

## US-06: Currency Conversion
**As a** user, **I want** to see portfolio values in my preferred currency **so that** amounts are meaningful to me.

- [x] Portfolio currency selection (EUR, USD, GBP, CHF, JPY, CAD, AUD)
- [x] Stock price display currency (original or converted)
- [x] Cost basis calculated with historical exchange rate at purchase date
- [x] Current values calculated with live exchange rates
- [x] P&L = current value (current rate) − cost basis (historical rate)

## US-07: Extended Hours
**As a** user, **I want** to see pre-market and after-hours prices **so that** I know the latest available price.

- [x] Toggle to show/hide extended hours prices
- [x] Pre-market (orange) and Post-market (purple) badges
- [x] Portfolio values use extended hours prices when enabled

## US-08: Data Persistence
**As a** user, **I want** my data to be saved locally **so that** I can find it after restarting the app.

- [x] Data saved as JSON in `~/Library/Application Support/StockDock/data.json`
- [x] Debounced save (100ms) to avoid blocking the main thread
- [x] Immediate save on app termination
- [x] No redundant saves during initial load
- [x] No data sent to external servers

## US-09: Sleep/Wake
**As a** user, **I want** the app to handle Mac sleep and wake correctly **so that** it doesn't waste resources.

- [x] Sleep: disconnects WebSocket, stops timers
- [x] Wake: reconnects, full refresh of quotes and exchange rates

## US-10: Popover Interface
**As a** user, **I want** to access the app with a click on the menu bar icon **so that** everything is within reach.

- [x] Click opens popover with three tabs: Watchlist, Portfolios, Settings
- [x] Click outside closes the popover
- [x] On popover close, WebSocket subscriptions and menu bar updated
- [x] No Dock icon (`.accessory` policy)

## US-11: Settings
**As a** user, **I want** to customize the app behavior **so that** I can adapt it to my needs.

- [x] Stock price currency (original or converted)
- [x] Portfolio currency
- [x] Extended hours toggle
- [x] Menu bar display mode (8 options)

## US-12: Portfolio Export / Import
**As a** user, **I want** to export and import portfolios as JSON files **so that** I can back up my data or transfer it between machines.

- [x] Export all portfolios to a single JSON file via NSSavePanel
- [x] Export a single portfolio via right-click context menu → "Export"
- [x] Import portfolios from a JSON file via NSOpenPanel
- [x] Imported portfolios get new UUIDs to avoid conflicts
- [x] Duplicate portfolio names are auto-suffixed (e.g. "My Portfolio (2)")
- [x] Import button available in empty state (no portfolios)
- [x] Alert shown after import with count of imported portfolios
- [x] Error alerts for invalid/unreadable files

## US-13: 52-Week Range
**As a** user, **I want** to see where a stock's price sits within its 52-week range **so that** I can gauge at a glance whether it's near its yearly high or low.

- [x] 52-week high/low fetched from the same Yahoo quote calls (v7 + v8 fallback)
- [x] Range bar in the watchlist row with a marker showing the current position
- [x] 52-week low/high labels next to the bar (in the display currency)
- [x] `fiftyTwoWeekPosition` computed property (0…1), clamped, nil when range is missing/degenerate
- [x] 52-week data preserved across WebSocket ticks (WSS feed omits it)

## US-14: Price Alerts
**As a** user, **I want** to be notified when a stock reaches a condition I set **so that** I don't have to keep watching the prices.

- [x] Six conditions: price rises above / drops below, daily change up / down by %, near 52-week high / low
- [x] One-shot: an alert fires once, then disables itself (no spam)
- [x] Create via right-click on a watchlist stock → "Set Price Alert…"
- [x] Manage in Settings → Price Alerts: re-arm toggle, description, delete, "triggered" badge
- [x] Local macOS notification (title + condition + current price) via UNUserNotificationCenter
- [x] Evaluated on every quote update (WebSocket flush, REST poll, launch, wake)
- [x] Uses effective price so extended-hours moves can trigger alerts
- [x] During pre/post-market, waits for the real extended-hours price before firing — never triggers against the stale previous close
- [x] Alerts persisted in `data.json`
- [x] Notification layer is a safe no-op in dev runs without an app bundle

## US-15: Customizable Watchlist Display
**As a** user, **I want** to choose which details appear in each watchlist row **so that** I can keep the list as compact or detailed as I like.

- [x] Settings → Watchlist Display section with toggles
- [x] Toggle company name (second line under the symbol)
- [x] Toggle day range (low – high)
- [x] Toggle 52-week range bar
- [x] Toggle absolute change value (the % is always shown)
- [x] All default to ON (unchanged look on first run)
- [x] Changes apply instantly and are persisted in `data.json`
- [x] Reset to Defaults restores all toggles to ON

## US-16: Discord / Slack Webhook Notifications
**As a** user, **I want** my notifications mirrored to a Discord or Slack channel **so that** I get them on my phone too, not only on the Mac.

- [x] Settings → Notifications → Channels: enable toggle + webhook URL field + "Send test" button
- [x] Auto-detects Discord (rich embed, colored green/red/neutral) vs Slack (text) from the URL host
- [x] Only https URLs on known webhook hosts accepted (validated, SSRF-safe)
- [x] All notifications route through `NotificationManager.send` → both macOS and webhook
- [x] Price alerts inherit colored embeds (up = green, down = red)
- [x] Works in dev runs (webhook fires even when the macOS notification is a no-op)
- [x] Webhook config persisted in `data.json`

## US-17: Portfolio Notifications
**As a** user, **I want** per-portfolio notifications (e.g. "up €820 today") **so that** I'm told when a whole portfolio moves, not just single stocks.

- [x] Configured per portfolio via right-click on the portfolio header → "Notifications…"
- [x] Also listed and manageable (toggle / delete) under Settings → Notifications → Portfolio notifications, grouped by portfolio
- [x] Four modes: daily move ≥ %, daily move ≥ amount, daily summary, value milestone
- [x] Defaults: ±1% / ±250 (preferred currency) / milestone every 10,000 / summary after 22:00
- [x] Daily % / amount fire only on genuinely NEW extremes via per-direction high-water marks (`lastStepUp`/`lastStepDown`): going up notifies each new step, but retracing, hovering at a boundary, or oscillating across zero stays silent; reset each calendar day
- [x] Milestone primes silently on first observation (no spurious "reached X" on setup), then fires only on a new high or new low — bouncing around a milestone boundary does not re-notify
- [x] Daily summary fires once per day after the configured hour: value + today's P&L + top mover
- [x] Day change computed from the regular-session per-share change × quantity × FX rate (preferred currency)
- [x] Evaluated on every quote update (WebSocket flush, REST poll, launch, wake)
- [x] Burst de-dup backstop in `NotificationManager.send`: the exact same identifier cannot re-fire within 120s, so no notification type can spam at tick rate even on a logic regression
- [x] Anti-spam state (`lastStepUp`/`lastStepDown`/`lastDay`) and rules persisted in `data.json`, keyed by portfolio id
- [x] Notifications removed automatically when the portfolio is deleted
- [x] Pure firing logic unit-tested in `PortfolioAlertEvaluatorTests` (crossingStep, milestoneCrossed, shouldFireSummary)

## US-18: Configurable Menu Bar Colors
**As a** user, **I want** to customize the menu bar text colors **so that** they stay readable on any desktop background (issue #7.1).

- [x] Settings → "Menu Bar Colors": color pickers for Gain and Loss colors
- [x] Defaults to the system green/red (dynamic) until a custom color is chosen
- [x] "Use system text color" toggle: ignores gain/loss colors and uses the always-readable system label color; direction stays conveyed by `+/−` and `▲▼`
- [x] "Reset to default green/red" button
- [x] Colors persisted as hex in `data.json` (`gainColorHex`, `lossColorHex`, `menuBarUseSystemColor`); `ColorHex.swift` bridges hex ↔ `NSColor`/`Color`

## US-19: Language / Localization
**As a** user, **I want** to pick the app's language **so that** I can use StockDock in my own language (issue #7).

- [x] Settings → "Language": picker with English (default), Deutsch, Français, Español, Italiano, Português
- [x] In-app override of the locale via `\.environment(\.locale, …)` on `ContentView` — reactive, does not follow the system language
- [x] UI strings in `Resources/<lang>.lproj/Localizable.strings` (6 languages, keys = source English literals)
- [x] `release.sh` copies the `.lproj` into `Contents/Resources` (Bundle.main) so SwiftUI resolves them; `Package.swift` declares `defaultLocalization: "en"`; `Info.plist` lists `CFBundleLocalizations`
- [x] Verified with real SwiftUI renders that the chosen language (incl. English default) overrides the system language
- [ ] Note: in `swift run` (dev) translations don't show (SPM resources land in `Bundle.module`); only the bundled `.app` localizes

## US-20: Portfolio cost line readability
**As a** user, **I want** the `qty×avg price` line in the portfolio to always show its decimals **so that** large positions don't look truncated (issue #7 follow-up).

- [x] Fixed: the cost line scales to stay on one line instead of wrapping when the share count is large (was a layout wrap, not a formatting bug — decimals were correct)
- [x] Guardrail tests in `NumberFormattingTests` lock that the formatter keeps 2 decimals across locales (DE/EN), including whole and trailing-zero values

## US-21: Home tab — finance news
**As a** user, **I want** a Home tab with finance news **so that** I see what's moving the stocks I follow without leaving the menu bar.

- [x] New "Home" tab (first tab, `newspaper` icon) in the segmented control alongside Watchlist / Portfolios / Settings
- [x] News fetched from Yahoo Finance's public search endpoint (`v1/finance/search?newsCount=…`) — no API key, consistent with quotes/search
- [x] Feed is personalized: stories for the user's tracked symbols (watchlist + portfolio holdings, up to 6 concurrent queries), deduped by uuid and sorted newest-first (cap 40)
- [x] Fallback to general "stock market" news when nothing is tracked
- [x] Each row: thumbnail, headline (3 lines), publisher · relative time (localized); tap opens the article in the default browser
- [x] Each row shows a ticker pill for the reference stock (the tracked symbol the story was fetched for, via `NewsArticle.sourceSymbol`; falls back to the first related ticker for general-market news), emphasized with a filled accent background, plus up to 2 more related tickers as subtle pills
- [x] Throttled refresh (max once / 5 min) + force-refresh via the header refresh button while on Home; loading and empty states
- [x] `NewsArticle` decoding covered by `Tests/NewsArticleTests.swift` (all fields, smallest-thumbnail pick, missing-field fallbacks, required uuid)

## US-22: Sponsor the project
**As a** user, **I want** an easy way to support StockDock **so that** I can fund development while everything stays free.

- [x] Settings → "Enjoying StockDock?" section: copy clarifying the app is free & open source forever, with a pink "Become a Sponsor" button
- [x] Opens `https://github.com/sponsors/simonsruggi` in the browser
- [x] All strings localized across the 6 supported languages
