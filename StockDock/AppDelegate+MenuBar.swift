import AppKit
import Combine
import SwiftUI

extension AppDelegate {
    private var menuBarFontSize: CGFloat {
        CGFloat(storageService.fontSizeLevel) + 5
    }

    /// Renders one watchlist slide for the menu bar ticker. Applies issue #8.2
    /// (show name vs symbol) and #8.3 (no currency symbol for indices).
    private func watchlistSlide(symbol: String, upColor: NSColor, downColor: NSColor) -> (title: String, color: NSColor) {
        guard let quote = stockService.quotes[symbol] else {
            return (" \(symbol)", .secondaryLabelColor)
        }
        // #24: one call for both, so the ticker can't print a native figure
        // under the target currency's symbol while the FX pair is loading.
        let priced = stockService.priceDisplay(for: quote.currency)
        let pRate = priced.rate
        // #8.3: indices have no currency, so don't prefix a currency symbol.
        let isIndex = StorageService.isIndex(symbol: quote.symbol, type: storageService.type(for: quote.symbol))
        let sym = isIndex ? "" : StorageService.currencySymbol(for: priced.currency)
        // #8.2: prefer the readable name when the user opted in and it's available.
        // #12: a custom name, if the user set one, wins over both — it was chosen
        // precisely because neither the ticker nor Yahoo's name reads well up here.
        let fallback = (storageService.tickerShowName && !quote.name.isEmpty) ? quote.name : quote.symbol
        let label = storageService.displayLabel(for: quote.symbol, fallback: fallback)
        let sign = quote.changePercent >= 0 ? "+" : ""
        let priceValue = quote.displayPrice(extendedHours: storageService.showExtendedHours) * pRate
        let price = StorageService.formatNumber(priceValue, decimals: storageService.resolvedPriceDecimals(symbol: quote.symbol, price: priceValue))
        // Issue #10: optionally drop the percentage from the menu-bar ticker.
        let pctPart = storageService.menuBarHidePercent
            ? ""
            : " \(sign)\(String(format: "%.\(storageService.percentDecimals)f", quote.changePercent))%"
        let title = " \(label) \(sym)\(price)\(pctPart)"
        return (title, quote.changePercent >= 0 ? upColor : downColor)
    }

    func updateMenuBarTitle() {
        let displayMode = storageService.menuBarDisplay

        if displayMode == "ticker" || displayMode == "tickerPortfolio" {
            if tickerTimer == nil { startTickerTimer() }
        } else {
            stopTickerTimer()
        }

        // Icon only
        if displayMode == "icon" {
            statusItem?.button?.attributedTitle = NSAttributedString(string: "")
            statusItem?.button?.title = ""
            statusItem?.button?.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "StockDock")
            return
        }

        // Compute portfolio stats
        var totalValue = 0.0
        var totalCost = 0.0
        var dailyPnl = 0.0
        // #14: excluded portfolios never reach the menu bar figure.
        for portfolio in storageService.countedPortfolios {
            for holding in portfolio.holdings {
                if let quote = stockService.quotes[holding.symbol] {
                    let rate = stockService.rate(from: quote.currency)
                    let displayPrice = quote.displayPrice(extendedHours: storageService.showExtendedHours)
                    totalValue += holding.marketValue(currentPrice: displayPrice) * rate
                    dailyPnl += holding.dailyPnl(priceChange: quote.effectiveChange(extendedHours: storageService.showExtendedHours)) * rate
                    let costRate = stockService.rate(from: quote.currency, for: holding.purchaseDate)
                    totalCost += (holding.avgPrice * holding.quantity) * costRate
                }
            }
        }
        let totalPnl = totalValue - totalCost
        let totalPnlPct = totalCost > 0 ? (totalPnl / totalCost) * 100 : 0

        // Find best/worst watchlist stock by daily change %
        let bestStock = storageService.watchlist.compactMap { stockService.quotes[$0] }
            .max(by: { $0.changePercent < $1.changePercent })
        let worstStock = storageService.watchlist.compactMap { stockService.quotes[$0] }
            .min(by: { $0.changePercent < $1.changePercent })

        let currSymbol = StorageService.currencySymbol(for: storageService.preferredCurrency)
        let title: String
        let color: NSColor

        // Issue #7.1: customizable gain/loss colors. "Use system color" overrides both
        // with the always-readable label color (direction stays in the +/- and ▲▼).
        let upColor: NSColor = storageService.menuBarUseSystemColor ? .labelColor : storageService.gainColor
        let downColor: NSColor = storageService.menuBarUseSystemColor ? .labelColor : storageService.lossColor

        switch displayMode {
        case "dailyPnl":
            title = " Daily P&L \(StorageService.formatAmount(dailyPnl, symbol: currSymbol, decimals: storageService.amountDecimals, signed: true))"
            color = dailyPnl >= 0 ? upColor : downColor

        case "totalValue":
            title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol, decimals: storageService.amountDecimals))"
            color = totalPnl >= 0 ? upColor : downColor

        case "pnlPercent":
            let sign = totalPnlPct >= 0 ? "+" : ""
            title = " P&L \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
            color = totalPnlPct >= 0 ? upColor : downColor

        case "pnlFull":
            let pctSign = totalPnlPct >= 0 ? "+" : ""
            let pctPart = storageService.menuBarHidePercent ? "" : " (\(pctSign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%)"
            title = " \(StorageService.formatAmount(totalPnl, symbol: currSymbol, decimals: storageService.amountDecimals, signed: true))\(pctPart)"
            color = totalPnl >= 0 ? upColor : downColor

        case "bestStock":
            if let best = bestStock {
                let sign = best.changePercent >= 0 ? "+" : ""
                title = " \(storageService.displayLabel(for: best.symbol, fallback: best.symbol)) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", best.changePercent))%"
                color = best.changePercent >= 0 ? upColor : downColor
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "worstStock":
            if let worst = worstStock {
                let sign = worst.changePercent >= 0 ? "+" : ""
                title = " \(storageService.displayLabel(for: worst.symbol, fallback: worst.symbol)) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", worst.changePercent))%"
                color = worst.changePercent >= 0 ? upColor : downColor
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "bestWorst":
            if let best = bestStock, let worst = worstStock, best.symbol != worst.symbol {
                let bSign = best.changePercent >= 0 ? "+" : ""
                let wSign = worst.changePercent >= 0 ? "+" : ""
                title = " ▲\(storageService.displayLabel(for: best.symbol, fallback: best.symbol)) \(bSign)\(String(format: "%.\(storageService.percentDecimals)f", best.changePercent))%  ▼\(storageService.displayLabel(for: worst.symbol, fallback: worst.symbol)) \(wSign)\(String(format: "%.\(storageService.percentDecimals)f", worst.changePercent))%"
                color = .labelColor
            } else if let best = bestStock {
                let sign = best.changePercent >= 0 ? "+" : ""
                title = " \(storageService.displayLabel(for: best.symbol, fallback: best.symbol)) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", best.changePercent))%"
                color = best.changePercent >= 0 ? upColor : downColor
            } else {
                title = " --"
                color = .secondaryLabelColor
            }

        case "portfolioRecap":
            let sign = totalPnlPct >= 0 ? "+" : ""
            let pctPart = storageService.menuBarHidePercent ? "" : " \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
            title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol, decimals: storageService.amountDecimals))\(pctPart)"
            color = totalPnl >= 0 ? upColor : downColor

        case "ticker":
            // #8.1: cycle in the user-selected order (as added / by type / alphabetical).
            let symbols = StorageService.tickerOrder(storageService.watchlist, mode: storageService.watchlistSort, types: storageService.symbolType)
            if symbols.isEmpty {
                title = " --"
                color = .secondaryLabelColor
            } else {
                let symbol = symbols[tickerIndex % symbols.count]
                (title, color) = watchlistSlide(symbol: symbol, upColor: upColor, downColor: downColor)
            }

        case "tickerPortfolio":
            // Issue #7.3: cycle through the watchlist AND a portfolio recap slide.
            let symbols = StorageService.tickerOrder(storageService.watchlist, mode: storageService.watchlistSort, types: storageService.symbolType)
            // #14: counted only — otherwise a user whose sole portfolio is excluded
            // would cycle an empty "0.00 +0.0%" recap slide.
            let hasPortfolio = storageService.countedPortfolios.contains { !$0.holdings.isEmpty }
            let slideCount = symbols.count + (hasPortfolio ? 1 : 0)
            if slideCount == 0 {
                title = " --"
                color = .secondaryLabelColor
            } else {
                let index = tickerIndex % slideCount
                if index < symbols.count {
                    // Watchlist slide (same rendering as the "ticker" mode)
                    (title, color) = watchlistSlide(symbol: symbols[index], upColor: upColor, downColor: downColor)
                } else {
                    // Portfolio recap slide
                    let sign = totalPnlPct >= 0 ? "+" : ""
                    title = " \(StorageService.formatAmount(totalValue, symbol: currSymbol, decimals: storageService.amountDecimals)) \(sign)\(String(format: "%.\(storageService.percentDecimals)f", totalPnlPct))%"
                    color = totalPnl >= 0 ? upColor : downColor
                }
            }

        default: // "pnl"
            title = " P&L \(StorageService.formatAmount(totalPnl, symbol: currSymbol, decimals: storageService.amountDecimals, signed: true))"
            color = totalPnl >= 0 ? upColor : downColor
        }

        statusItem?.button?.image = nil
        statusItem?.button?.title = title

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: FontRegistration.monospacedDigitsFont(size: menuBarFontSize, weight: .medium)
        ]
        statusItem?.button?.attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }
}
