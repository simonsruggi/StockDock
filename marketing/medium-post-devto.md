---
title: "StockDock 1.9.0: My Free, Open-Source Stock Tracker for Mac Just Became a Full Desktop App"
published: false
description: "StockDock 1.9.0 turns my free, open-source macOS menu bar stock tracker into a full desktop app — no account, no subscription, no tracking."
tags: macos, swift, opensource, showdev
cover_image: https://raw.githubusercontent.com/simonsruggi/StockDock/main/screenshots/desktop.png
canonical_url:
---

A year ago I got tired of opening a browser tab every time I wanted to check my portfolio. So I built **StockDock** — a tiny macOS menu bar app that shows your stocks, crypto, and P&L in real time, one click away, with no account and no subscription.

It's stayed **100% free and open source** the whole way. And with the release I just shipped — **1.9.0** — it grew up: StockDock is now a full desktop app *and* a menu bar app at the same time.

Let me show you what's new, and why "free and open source, forever" is a promise I actually mean.

---

## The one-line pitch

**StockDock is a free, open-source macOS app for tracking stocks, ETFs, indices, crypto, and your portfolio P&L in real time — from your menu bar or a full desktop window.**

No account. No API keys. No subscription. No tracking. Your watchlist and portfolio never leave your Mac.

```bash
brew install simonsruggi/tap/stockdock
```

---

## What's new in 1.9.0 — a full desktop window

Until now, StockDock lived entirely in your menu bar: click the icon, a popover drops down, done. That's still there — but sometimes you want room to breathe. So now the popover has an **Open** button that expands StockDock into a complete desktop window.

![StockDock desktop window — portfolio overview with value chart, P&L, allocation, and movers](https://raw.githubusercontent.com/simonsruggi/StockDock/main/screenshots/desktop.png)

News, Watchlist, Portfolios, and Settings in one spacious, redesigned view — with live charts, allocation breakdowns, and your day's movers. Everything stays perfectly in sync with the menu bar: change something in the window and the popover updates instantly, and vice versa.

It's the same app, the same data, two ways to look at it. Glance at the menu bar during the day; open the full window when you want to dig in.

Also new in 1.9.0:

- **Price & After-hours side by side** — separate, individually sortable columns for the regular price and the pre/post-market price (each with its own % move).
- **News search** — filter stories by headline, ticker, or publisher.
- **Add to portfolio from a stock's detail** — open any symbol and add it as a position in one click.
- **Sharper precision** — forex pairs and sub-dollar prices now show the decimals that actually matter (`0.7119`, not `0.71`).
- **Decimal controls** — choose how many decimals to show for percentages and values, or hide the percentage in the menu bar entirely.

---

## The problem I was solving

Most ways to watch the market fall into two camps:

1. **Full trading platforms** (Robinhood, IBKR, Trading 212) — great for trading, overkill for glancing. They take over the screen and drain the battery.
2. **Web dashboards** (Yahoo Finance, Google Finance) — a browser tab you have to keep open, buried in ads and distractions.

I wanted the in-between: a quiet widget that just shows the numbers. Like the battery percentage or Wi-Fi status in your menu bar — but for your portfolio. StockDock is that. And now, when you *do* want the full picture, it's one click away.

---

## What you can track

Stocks, ETFs, indices (S&P 500, NASDAQ…), crypto, and forex — anything with a Yahoo Finance symbol. Search by **symbol**, **company name**, or **ISIN** (`AAPL`, `Tesla`, `IE00B4L5Y983`).

![StockDock watchlist tab with live prices and 52-week range bars](https://raw.githubusercontent.com/simonsruggi/StockDock/main/screenshots/watchlist.png)

A few things people tend to like:

- **Menu bar P&L** — pick what shows up top: P&L, total value, % change, best/worst mover, or just an icon. Green when you're up, red when you're down.
- **Multi-currency portfolios** — hold mixed-currency positions and see totals converted to yours, with the historical exchange rate applied to your cost basis so P&L stays honest.
- **Long/short + leverage** — optional, off by default, with correct sign and exposure math.
- **Alerts that reach you** — one-shot price alerts and per-portfolio notifications, delivered as native macOS notifications and optionally mirrored to a **Discord or Slack webhook**.
- **52-week range bars**, **extended-hours prices**, **export/import to JSON** — the details that make it feel finished.

---

## Private by design (and I mean it)

This part matters to me more than any feature:

- Everything is stored locally in `~/Library/Application Support/StockDock/data.json`.
- The app only ever talks to Yahoo Finance's public endpoints (and your own webhook, if you set one up).
- **No account. No login. No analytics. No telemetry.** I have literally no way of knowing how many people use StockDock.
- It's fully open source — you can read every line before you trust it with your watchlist.

In a world where every app wants your email, StockDock wants nothing.

---

## Why open source, and how you can help

StockDock is MIT-licensed and it will **always** be free — no paid tier, no premium lock, no "unlock pro" wall. That's a deliberate choice, not a soft launch for a subscription later.

But that same privacy stance means I'm flying blind: no analytics means the only signal I ever get that the app is worth maintaining is a **GitHub star**. So if StockDock is useful to you, the single most helpful thing you can do — and it's free — is [⭐️ star the repo](https://github.com/simonsruggi/StockDock).

And if you want to go further, you can [❤️ sponsor me on GitHub](https://github.com/sponsors/simonsruggi). It changes nothing about the app — every feature stays free for everyone — it just helps me keep building. Either way, thank you.

---

## Install

**Homebrew** (recommended):

```bash
brew install simonsruggi/tap/stockdock
```

Or grab the latest `StockDock.zip` from [GitHub Releases](https://github.com/simonsruggi/StockDock/releases/latest), unzip, and drop it in `/Applications`.

The app is code-signed, notarized by Apple, and auto-updates via Sparkle — install once and forget about it. Requires **macOS 14 Sonoma or later**, and runs natively on both Apple Silicon and Intel.

---

## For the nerds

- **Swift + SwiftUI** — native macOS, no Electron, no web views.
- **Yahoo Finance WebSocket** — real-time prices (~1 tick/second), decoded from binary with **swift-protobuf**.
- **Sparkle** — seamless background auto-updates.
- **Universal binary** — ARM64 + x86_64 in one small, fast app.

Six languages, too: English, German, French, Spanish, Italian, and Portuguese.

---

## Try it

If you invest or trade and you're on a Mac, StockDock takes about ten seconds to install and you might never close it again.

- **GitHub:** [github.com/simonsruggi/StockDock](https://github.com/simonsruggi/StockDock)
- **Install:** `brew install simonsruggi/tap/stockdock`
- **Star it** if it's useful — it genuinely helps me keep going.

---

*I'm Simone Ruggiero, an indie developer building apps for iOS and macOS. More of my work at [simoneruggiero.com](https://simoneruggiero.com).*
