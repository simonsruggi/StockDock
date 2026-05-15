# User Stories — StockDock

## US-01: Menu Bar Display
**As a** user, **I want** to see a summary of my portfolio in the macOS menu bar **so that** I can monitor my investments at a glance.

- [x] Menu bar shows P&L in the chosen format (absolute, %, both, total value, best/worst stock, icon only)
- [x] Values update in real time with prices
- [x] Green (positive) / red (negative) color coding
- [x] 8 display modes: P&L, P&L %, P&L + %, Total Value, Best Stock, Worst Stock, Best & Worst, Icon Only

## US-02: Watchlist
**As a** user, **I want** to maintain a watchlist of stocks **so that** I can monitor their prices.

- [x] Search stocks by symbol, name or ISIN
- [x] Add/remove stocks from the watchlist
- [x] Current price, daily change %, extended hours prices
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
