# Changelog

Every released version of StockDock. Updates are delivered through Sparkle
(auto-update) and Homebrew; each version is also a
[GitHub release](https://github.com/simonsruggi/StockDock/releases).

## 1.9.14 — 2026-08-23

*See the day's move on every position*

- **A Change column in the Portfolio window.** The holdings list showed Last, Value, P&L and Weight, but not the figure that moves minute to minute — how much each position has changed today. There's now a Change column between Last and Value, showing the day's move in your currency with the percent below it, in the usual green/red. The figures drop trailing zeros, so a move reads as +12 rather than +12.00.

With thanks to [Greg](https://github.com/barereef), whose pull request added this.

## 1.9.13 — 2026-08-06

*The 24H chart stops going blank*

- **24H draws a chart outside market hours.** Every evening, all weekend and on holidays, the 24H range showed "Value history builds up day by day" instead of a curve — even on a portfolio with years of history, and even while the other ranges drew perfectly. Yahoo's intraday endpoint returns nothing until today's session actually prints, so the app now fetches two days and charts the most recent session that traded, the way Stocks shows the previous session when the market is shut. Sessions are split on the gap between bars rather than the calendar day, so a US session isn't cut in half for anyone east of London.
- **Chart gridlines you can actually see.** They reused the border hairline at 7% alpha — and the horizontal axis then halved it again — which left the plot area looking empty. Gridlines now have their own colour, set separately for the light and dark themes, on both axes of both charts. The portfolio value chart had no vertical gridlines at all.

With thanks to [Pete Kasson](https://github.com/pete-kasson), whose issue drove this release.

## 1.9.12 — 2026-08-05

*Name your symbols, and a portfolio that doesn't count*

- **Give a symbol the name you actually call it.** `CAD/USD` and `^GSPC` tell you nothing at a glance and eat menu bar space. Right-click any symbol in your watchlist → **Rename…** and call it *CAD* or *S&P*. The name shows in the menu bar ticker and in your lists; the real ticker is still there, on the second line. Clearing the field puts the ticker back.
- **A portfolio can sit outside your total.** Right-click a portfolio → **Count in Total** and uncheck it. Paper-trade an idea, or follow a position you haven't taken, without it moving what you're actually worth. It stays a real portfolio — its own chart, history, notifications and export are untouched — it just doesn't reach the menu bar, "All Portfolios" or the total at the bottom of the window. Excluded portfolios are greyed in the list so you can see it at a glance.
- **Your positions show how many shares you hold.** The share count was only in the compact list and the holding detail; it's now on the positions row in the Portfolio window, next to the company name.
- **Charts open where you left them.** The range picker used to snap back to 1M (or All, for the portfolio chart) every single time. It now remembers the last range you picked, separately for each kind of chart.

With thanks to [macOS-Mavericks](https://github.com/macOS-Mavericks) and [Pete Kasson](https://github.com/pete-kasson), whose issues drove this release.

## 1.9.11 — 2026-08-03

*Today's P&L in the menu bar*

- **A new "Daily P&L" display option.** The menu bar could show your total P&L, its percentage or the portfolio value — but not the one figure you check most during the session: how much you are up or down *today*. Pick it under Settings → Display.
- **It counts what your positions really are.** The daily figure converts every holding into your preferred currency, follows short positions in the right direction, applies leverage, and uses the extended-hours price when you have extended hours turned on — exactly like the Portfolio window's TODAY row.

With thanks to [Jérôme Siau](https://github.com/JeromeSiau), who contributed this feature.

## 1.9.10 — 2026-07-30

*The value chart starts when you actually bought*

- **"All" no longer invents decades of history.** The estimated portfolio curve was reconstructed from each stock's full price history, so a position opened this year could be charted all the way back to the 1990s or 2000s — whenever that symbol first traded. It now starts at your oldest purchase.
- **Each position joins the curve on its own purchase date.** The chart steps up as you actually built the portfolio, instead of pretending you always held today's shares. Holdings saved without a purchase date are unchanged.
- **A finer curve on "All".** With a realistic window, the range now draws the daily series when your oldest purchase fits inside it, rather than a handful of monthly steps.
- **Clearer dates on the axis.** Labels follow the period actually drawn, and the year is spelled out in full — "Jan 05" could be read as the 5th of January rather than January 2005.

Your figures are unaffected: total P&L, invested amount and the all-time percentage have always come from your real cost and current value, never from the estimated curve. Only the shape of the chart was wrong.

## 1.9.9 — 2026-07-28

*Much lighter on your Mac*

- **Idle CPU use is down to near zero.** With the Portfolio window open, StockDock used to sit around 60-70% CPU for as long as the market was open — enough to warm up the machine and slow everything else down. In the background it now measures about 0.1%.
- **Live prices no longer animate non-stop.** Price-driven animations were slower to settle than the once-a-second price feed, so the app was redrawing continuously and never went idle. They are now short and snappy, and finish between updates.
- **The Portfolio window does far less work per update.** Positions are valued once per refresh instead of a dozen times, and the value chart no longer re-animates every mark on every tick.
- **Updates slow down when you're in another app.** Prices refresh once a second while you're looking at StockDock, and less often when you're not — bringing the app back to the front shows the latest figures immediately.

No feature or visual changes: everything looks and behaves exactly as before, it just costs a fraction of the CPU.

## 1.9.8 — 2026-07-28

*Current price next to your average buy price*

- **Cost and market price side by side.** Each line of the per-stock average buy price block now shows the live price too — *avg* is what you paid, *now* is what it trades at — so you can read your entry and the market in one glance, without opening the position.
- **Same currency, same precision.** The current price uses the stock's own price currency and follows your extended-hours setting, exactly like the rest of the app.

## 1.9.7 — 2026-07-23

*Average buy price across all your portfolios*

- **Global cost at a glance.** The portfolios list now shows, right under the overall *Total value*, one line per stock with its average buy price — weighted across *every* portfolio you own it in — and the current price return next to it, in green or red.
- **See your true entry.** If you hold the same ticker in more than one portfolio, you no longer have to average it by hand: the number you see is the real blended cost.

## 1.9.6 — 2026-07-23

*Edit a holding from its detail page*

- **Edit button where you expect it.** Open any position from a portfolio and there's now a pencil in the header — tap it to edit shares, price, date, or leverage. Previously editing was only reachable by right-clicking the row, so it was easy to miss.

## 1.9.5 — 2026-07-20

*Portfolio performance — fixed*

- **"Today" now counts pre/post-market.** The portfolio value already used the extended-hours price, but the daily change only looked at the regular session — so on a gap day the value could be up while "today" showed down. They now share the same baseline and always agree.
- **Accurate performance pills.** The header pill now shows the real figure for each range: *today* on 24H (matching the TODAY stat), and your true *all-time* P&L on All (no more inflated numbers from the reconstructed curve).
- **Cleaner 24H chart.** The intraday curve is pinned to your live portfolio value, so it no longer ends below the headline total.

## 1.9.4 — 2026-07-17

*Gain/loss colors, everywhere*

- Your custom colors now apply across the whole app — the gain and loss colors you pick (Settings › Menu Bar › Colors) are no longer limited to the menu bar. They now color the watchlist, portfolios, movers and every P&L figure in the app.
- Always editable — the color pickers stay available even when "use system color in the menu bar" is on, so you can keep the menu bar text neutral while still theming the rest of the app.
- Leave a color unset to fall back to the classic emerald / terracotta.

## 1.9.3 — 2026-07-17

*Portfolio chart*

- Change now follows the selected period — the percentage next to your portfolio value updates with the range you pick (24H, 7D, 1M, 1Y, All) instead of always showing the day's move.
- No more text over the curve — the value and change now sit above the chart, so the line never hides behind them, on any period.
- Smoother transitions — switching periods crossfades and the curve settles in gently as data loads.
*Settings, tidied up*

- Collapsible categories — the menu bar Settings are grouped (General, Currency, Positions & Market, Watchlist, Menu Bar, Notifications, About) and each section expands only when you need it.
- Support options — you can now star the repo on GitHub as well as sponsor. StockDock stays free and open source.

## 1.9.2 — 2026-07-16

*Your app, your way*

- Dark mode is back — Settings › Appearance now has a Theme control: follow the system, or force Light or Dark. No more being stuck on the bright theme.
- Hide the News tab — a new "Show News tab" switch removes the Home/News feed entirely. For the record, the feed never ran in the background: it only fetched while its tab was open, throttled, no battery or data drain when hidden.
*Fixed*

- Tab bar label — the Settings tab no longer shows a stray "Portfolios" label next to it.

## 1.9.1 — 2026-07-16

*Improved: a clearer watchlist*

- Every price now shows its own % move right below it — the regular price carries today's change, the after-hours price carries the pre/post-market change. No more guessing which percentage belongs to which number.
- The live session leads — during pre/post-market the after-hours price and its % move come forward, while the previous close steps back to context. In regular hours it's the other way around, so what's moving now always reads first.
- Sort by what you see — clicking a column header sorts by that column's % move (not the raw after-hours price). Biggest movers on top.
*Fixed*

- “Show extended hours” now works in the watchlist — turning it off hides the after-hours column and shows only regular market values.

## 1.9.0 — 2026-07-16

*New: the full desktop window*

- Try the new desktop app — StockDock now has a complete window, not just the menu-bar popover. Open the popover and click the “Open” button to try the new view: News, Watchlist, Portfolios and Settings in a spacious, redesigned interface. Everything stays in sync with the menu bar.
*Added*

- Watchlist — Price & After-hours side by side — separate columns for the regular price and the pre/post-market price (with its own % move). Every column is sortable.
- Search your news — filter stories by headline, ticker or publisher.
- Add to portfolio from a stock’s detail — open any symbol and add it as a position in one click.
- More price precision — forex pairs and sub-dollar prices now show extra decimals (e.g. 0.7119 instead of 0.71).
- Decimal controls — choose how many decimals to show for percentages and for values, and a menu-bar option to hide the percentage entirely.

## 1.8.2 — 2026-07-15

*Fixed*

- Prices no longer freeze — fixed a bug where live prices could stop updating after your Mac woke from sleep or after the app had been running for a long time. StockDock now detects a stalled connection and reconnects automatically.
- Correct price outside market hours — with extended hours turned off, prices now stay on the last regular close during pre-market and after-hours instead of briefly showing the extended-hours price.

## 1.8.1 — 2026-07-13

*Improved*

- Ticker on every news story — each story in the Home feed now shows a clear ticker badge for the stock it's about (the one you follow), plus any other related tickers, so you can tell at a glance which of your holdings the news concerns.
- Faster update checks — StockDock now checks for new versions a few times a day, so you get improvements sooner.

## 1.8.0 — 2026-07-13

*New*

- Home tab — finance news — a new Home tab shows the latest finance news for the stocks you follow (and general market news when your watchlist is empty). Each story shows the source, when it was published and related tickers; tap to open it in your browser. No account, no API keys — same privacy-first approach as the rest of the app.
- Support the project — StockDock is free and open source, and always will be. If it's useful to you, there's now a "Become a Sponsor" button in Settings to help fund development. Every feature stays free for everyone.
*Fixed*

- More reliable price updates — a single delisted or suspended ticker in your watchlist could stop live prices from loading for every other symbol. Prices now load reliably even when one ticker returns incomplete data.

## 1.7.2 — 2026-06-25

*New*

- Long / Short picker — when Advanced positions is on, add/edit holding now has a clear Long / Short selector instead of typing a negative quantity. Works in the quick "Add to Portfolio" sheet from the watchlist right-click too.
- Clear all — one-tap buttons to delete all price alerts, and all portfolio notifications, from Settings → Notifications.
*Fixed*

- Too many portfolio notifications — the "Daily move ≥ %/amount" notification fired at every step (+1%, +2%, +3%…) on a trending day. It now fires at most once per direction per day: once when today's move first crosses +threshold and once when it crosses −threshold.

## 1.7.1 — 2026-06-25

*New*

- Short positions & leverage — enable them in Settings → Advanced, then enter a negative quantity for a short and an optional leverage multiplier per holding. P&L, exposure and daily change are computed correctly in every case, so a portfolio can be tracked as a relative long/short basket. Long-only stays the default and untouched.

## 1.7.0 — 2026-06-25

*New*

- Show name instead of symbol — optional toggle so the menu bar ticker shows the readable name (e.g. "S&P 500") instead of the raw symbol ("^GSPC"). Settings → Menu Bar Display, in the Ticker modes.
- Ticker order — choose how watchlist entries cycle in the menu bar: as added, grouped by type (stocks, ETFs, indices, futures…), or alphabetical.
*Fixed*

- No currency symbol on indices — index values (e.g. S&P 500, DAX) no longer show a currency prefix, since an index has no associated currency.

## 1.6.2 — 2026-06-23

*Fixed*

- Pre-market alerts — price alerts no longer fire against the previous day's close while pre-market or after-hours data hasn't arrived yet. An alert now waits for the real extended-hours price, so you won't get a spurious "now $1,100" notification at the previous close.

## 1.6.1 — 2026-06-15

*New*

- Languages — StockDock is now localized in English, German, French, Spanish, Italian and Portuguese. Pick one in Settings → Language (English stays the default).
- Custom menu bar colors — set your own gain/loss colors in Settings → Menu Bar Colors, or switch on "Use system text color" to stay readable on any background (up/down is still shown by + / − and ▲ ▼).
- Ticker + Portfolio cycle — a new menu bar mode that rotates through your watchlist and a portfolio summary in the same cycle.
- 2-decimal percentages — optional toggle to show percentages with two decimals instead of one (off by default to keep the bar compact).
*Fixed*

- Portfolio cost line — the quantity × average price line no longer wraps and hides its decimals for large positions.

## 1.6.0 — 2026-06-12

*Improved*

- Thousands separator — numbers above 1,000 are now grouped for readability across the menu bar, watchlist, portfolio, alerts and notifications (e.g. €23.922,36 instead of €23922,36). Grouping and decimal separators follow your system locale.

## 1.5.2 — 2026-06-11

*Fixed*

- No more notification spam — portfolio notifications (daily move and value milestones) now fire only on genuinely new highs or lows. When your portfolio hovers around a threshold or bounces back and forth, you'll no longer get a flood of repeat alerts. You still get one ping for each new step up or down.
*Improved*

- Version shown in the header — the popover header now always shows the app version next to the StockDock title.

## 1.5.1 — 2026-06-11

*Improved*

- Portfolio notifications now show what moved — daily move alerts and the daily summary list your holdings with their change % and value (biggest movers first), instead of just a single top mover. At a glance you can see which stocks drove the change. Works in the macOS notification and in your Discord/Slack mirror.

## 1.5.0 — 2026-06-08

*New*

- Portfolio notifications — get notified when a whole portfolio moves, not just single stocks. Right-click a portfolio → “Notifications…” and pick a mode: daily move over a % or amount, a value milestone, or a once-a-day summary with today's P&L and top mover.
- Discord & Slack — mirror every notification to a Discord or Slack channel so you get them on your phone too. Set your webhook in Settings → Notifications and hit “Send test”. Messages arrive as StockDock with the app icon, colored green/red by direction.
- Unified Notifications settings — webhook channels, price alerts and portfolio notifications are now all in one place, with toggles and delete for each.
*Improved*

- Currency symbol now appears before the amount everywhere (e.g. €42,300.00, +€820.00).

## 1.4.0 — 2026-06-04

*New*

- Price alerts — get a notification when a stock rises above or drops below a price, moves more than a set % in a day, or comes near its 52-week high or low. Right-click a stock in the watchlist to set one. Alerts fire once, then disable themselves so you're never spammed.
- 52-week range bar — each watchlist row now shows where the price sits between its yearly low and high at a glance.
- Manage alerts in Settings — re-arm, review or delete your alerts from the new Price Alerts section.
- Customizable watchlist — new Watchlist Display settings let you show or hide the company name, day range, 52-week bar and absolute change in each row.
