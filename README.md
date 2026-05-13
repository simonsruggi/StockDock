# StockDock

A lightweight macOS menu bar app for tracking stocks and portfolios in real time.

Built with SwiftUI. No account required, no API keys needed — data comes directly from Yahoo Finance.

## Screenshots

| Menu Bar | Watchlist | Portfolios | Settings |
|---|---|---|---|
| ![Menu Bar](screenshots/menubar.png) | ![Watchlist](screenshots/watchlist.png) | ![Portfolios](screenshots/portfolio.png) | ![Settings](screenshots/settings.png) |

## Features

- **Menu Bar P&L** — See your portfolio performance at a glance, always visible
- **Watchlist** — Track any stock by symbol with live prices and daily change
- **Portfolios** — Create multiple portfolios with holdings, average cost, and P&L
- **Extended Hours** — Pre-market and after-hours prices with PRE/POST badges
- **Currency Conversion** — Convert stock prices and portfolio values to your preferred currency
- **Customizable Menu Bar** — Choose what to display: P&L, total value, percentages, best/worst stock, or just an icon
- **Auto-Updates** — Updates are delivered automatically via Sparkle, no manual downloads needed

## Install

### Homebrew (recommended)

```bash
brew install simonsruggi/tap/stockdock
```

The app updates itself automatically via Sparkle — no need to run `brew upgrade`.

### Download

1. Download the latest `StockDock.zip` from [Releases](https://github.com/simonsruggi/StockDock/releases/latest)
2. Unzip and move `StockDock.app` to `/Applications`
3. Launch — the app appears in the menu bar (no Dock icon)

### Build from source

Requires **Xcode 15+** and **macOS 14 Sonoma** or later.

```bash
git clone https://github.com/simonsruggi/StockDock.git
cd StockDock
xcodebuild -scheme StockDock -configuration Release -destination 'platform=macOS' -derivedDataPath .build/xcode build
```

The app bundle will be at `.build/xcode/Build/Products/Release/`.

## Usage

### Watchlist

Add stocks by clicking **Add stock** at the bottom of the Watchlist tab. Search by symbol, company name, or ISIN (e.g. `AAPL`, `Tesla`, `IE00B4L5Y983`). Stocks show:

- Current price with currency symbol
- Daily change (absolute and percentage)
- Extended hours price when available (PRE/POST badge)

Right-click a stock to remove it or add it to a portfolio.

### Portfolios

1. Click the **Portfolios** tab
2. Click **New portfolio** to create one
3. Click **Add holding** to add a stock with quantity and average price

Each portfolio shows:
- **Total value** in your chosen currency
- **P&L** (profit & loss) in absolute and percentage terms
- Per-holding breakdown with price, value, and individual P&L

Right-click a holding to edit or delete it.

### Settings

Click the gear icon tab to configure:

| Setting | Description |
|---|---|
| **Stock Price Currency** | Convert all displayed prices to a single currency, or keep original |
| **Portfolio Currency** | Base currency for portfolio totals and P&L (EUR, USD, GBP, CHF, JPY, CAD, AUD) |
| **Show Extended Hours** | Toggle pre-market and after-hours prices on/off — affects prices, P&L, and menu bar |
| **Menu Bar Display** | What appears in your menu bar (see below) |

### Menu Bar Display Options

| Option | Example |
|---|---|
| P&L | `P&L +321.09€` |
| P&L % | `P&L +2.3%` |
| P&L + % | `+321.09€ (+2.3%)` |
| Total Value | `14396.67€` |
| Best Stock | `AAPL +1.2%` |
| Worst Stock | `TSLA -0.8%` |
| Best & Worst | `▲AAPL +1.2%  ▼TSLA -0.8%` |
| Icon Only | Chart icon |

Best/Worst are based on daily change % from your watchlist.

## Updates

StockDock checks for updates automatically on launch via [Sparkle](https://sparkle-project.org/). You can also check manually from **Settings → Check for Updates**. No action needed — updates install seamlessly in the background.

## Data & Privacy

- Real-time prices via Yahoo Finance WebSocket (~1 update/sec per symbol)
- REST polling every 5 min as fallback for exchange rates
- All data is stored locally in `~/Library/Application Support/StockDock/data.json`
- No data is sent anywhere — the app only talks to Yahoo Finance APIs
- No account required, no API keys needed

## Tech Stack

- Swift 5.9 / SwiftUI
- macOS 14+ (Sonoma)
- Yahoo Finance WebSocket (real-time) + REST API (fallback)
- [Sparkle](https://sparkle-project.org/) for auto-updates
- [swift-protobuf](https://github.com/apple/swift-protobuf) for WebSocket decoding

## License

MIT
