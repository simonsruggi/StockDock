import SwiftUI

extension AppDelegate {
    // MARK: - WebSocket

    func startWebSocket() {
        let symbols = collectSymbols()
        guard !symbols.isEmpty else { return }

        webSocketService.onTick = { [weak self] ticker in
            guard let self else { return }
            self.pendingTicks.append(ticker)
            self.scheduleTickFlush()
        }

        webSocketService.connect(symbols: Array(symbols))
    }

    /// Flush buffered ticks at `tickFlushInterval` to avoid @Published spam
    private func scheduleTickFlush() {
        guard tickBatchTimer == nil else { return }
        tickBatchTimer = Timer.scheduledTimer(withTimeInterval: tickFlushInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickBatchTimer = nil
                self.flushTicks()
            }
        }
    }

    func flushTicks() {
        guard !pendingTicks.isEmpty else { return }
        let ticks = pendingTicks
        pendingTicks.removeAll(keepingCapacity: false)

        // Keep only the latest tick per symbol
        var latest: [String: Yaticker] = [:]
        for tick in ticks {
            latest[tick.id] = tick
        }

        var changed = false
        for (_, tick) in latest {
            if stockService.applyTick(tick) {
                changed = true
            }
        }

        if changed {
            updateMenuBarTitle()
            alertMonitor.check(quotes: stockService.quotes)
            portfolioMonitor.check()
        }
    }

    /// Captures a daily value/P&L snapshot per portfolio from the current quotes,
    /// for the Portfolio window's history chart. Skips a portfolio until every
    /// holding has a quote, so a partially-loaded feed can't record an understated
    /// value. `StorageService.recordSnapshot` keeps one entry per day.
    func recordSnapshots() {
        for portfolio in storageService.portfolios {
            guard !portfolio.holdings.isEmpty else { continue }
            let inputs: [PortfolioValuation.Input] = portfolio.holdings.compactMap { holding in
                guard let quote = stockService.quotes[holding.symbol] else { return nil }
                return PortfolioValuation.Input(
                    holding: holding,
                    price: quote.displayPrice(extendedHours: storageService.showExtendedHours),
                    rate: stockService.rate(from: quote.currency),
                    costRate: stockService.rate(from: quote.currency, for: holding.purchaseDate)
                )
            }
            guard inputs.count == portfolio.holdings.count else { continue }
            let totals = PortfolioValuation.totals(inputs)
            storageService.recordSnapshot(for: portfolio.id, totalValue: totals.value, totalCost: totals.cost)
        }
    }

    func collectSymbols() -> Set<String> {
        var symbols = Set(storageService.watchlist)
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                symbols.insert(holding.symbol)
            }
        }
        return symbols
    }

    // MARK: - Ticker Cycling

    func startTickerTimer() {
        guard tickerTimer == nil else { return }
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.tickerIndex += 1
                self.updateMenuBarTitle()
            }
        }
    }

    func stopTickerTimer() {
        tickerTimer?.invalidate()
        tickerTimer = nil
        tickerIndex = 0
    }

    // MARK: - REST Polling (exchange rates + fallback)

    func scheduleRESTPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.restPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isRefreshing else { return }
                let start = Date()
                self.refreshStartedAt = start
                defer { if self.refreshStartedAt == start { self.refreshStartedAt = nil } }
                let symbols = Array(StockService.collectSymbols(storageService: self.storageService))
                await self.stockService.fetchQuotes(symbols: symbols)
                await self.stockService.refreshExchangeRates(storageService: self.storageService)
                self.updateMenuBarTitle()
                self.alertMonitor.check(quotes: self.stockService.quotes)
                self.portfolioMonitor.check()
                self.recordSnapshots()
                // Supervisor: revive the WebSocket if it silently died, otherwise
                // just keep its subscriptions current.
                self.webSocketService.ensureConnected(symbols: Array(self.collectSymbols()))
            }
        }
    }

    // MARK: - Sleep / Wake

    @objc func handleSleep() {
        timer?.invalidate()
        timer = nil
        tickBatchTimer?.invalidate()
        tickBatchTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshStartedAt = nil
        tickerTimer?.invalidate()
        tickerTimer = nil
        pendingTicks.removeAll()
        webSocketService.disconnect()
    }

    @objc func handleWake() {
        refreshTask?.cancel()
        refreshTask = Task {
            let start = Date()
            refreshStartedAt = start
            defer { if refreshStartedAt == start { refreshStartedAt = nil } }
            await stockService.refreshAll(storageService: storageService)
            guard !Task.isCancelled else { return }
            updateMenuBarTitle()
            startWebSocket()
        }
        scheduleRESTPolling()
    }
}
