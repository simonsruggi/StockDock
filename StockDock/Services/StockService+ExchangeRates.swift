import Foundation

extension StockService {
    /// Refresh only exchange rates (current + historical). Called periodically while WSS handles quotes.
    func refreshExchangeRates(storageService: StorageService) async {
        let allSymbols = Self.collectSymbols(storageService: storageService)
        guard !allSymbols.isEmpty else { return }

        // Fetch exchange rates for all stock currencies toward both target currencies
        let preferredCurrency = storageService.preferredCurrency
        let priceCurrency = storageService.stockPriceCurrency

        // Collect all pairs we need: (from, to)
        var pairs = Set<String>() // "FROMTO" keys
        for symbol in allSymbols {
            guard let quote = quotes[symbol] else { continue }
            if quote.currency != preferredCurrency {
                pairs.insert("\(quote.currency)|\(preferredCurrency)")
            }
            if !priceCurrency.isEmpty && quote.currency != priceCurrency {
                pairs.insert("\(quote.currency)|\(priceCurrency)")
            }
        }

        // Evict exchange rates no longer needed
        let neededRateKeys = Set(pairs.compactMap { pair -> String? in
            let parts = pair.split(separator: "|")
            guard parts.count >= 2 else { return nil }
            return "\(parts[0])\(parts[1])"
        })
        let staleRateKeys = Set(exchangeRates.keys).subtracting(neededRateKeys)
        for key in staleRateKeys { exchangeRates.removeValue(forKey: key) }

        await withTaskGroup(of: Void.self) { group in
            for pair in pairs {
                let parts = pair.split(separator: "|")
                guard parts.count >= 2 else { continue }
                let from = String(parts[0])
                let to = String(parts[1])
                group.addTask { [weak self] in
                    await self?.fetchExchangeRate(from: from, to: to)
                }
            }
        }

        // Fetch historical rates for holdings with purchase date — skip if already cached
        var neededHistoricalKeys = Set<String>()
        var historicalKeysToFetch = Set<String>()
        for portfolio in storageService.portfolios {
            for holding in portfolio.holdings {
                guard let purchaseDate = holding.purchaseDate,
                      let quote = quotes[holding.symbol],
                      quote.currency != preferredCurrency
                else { continue }
                let dayStart = Calendar.current.startOfDay(for: purchaseDate)
                let ts = Int(dayStart.timeIntervalSince1970)
                let cacheKey = "\(quote.currency)\(preferredCurrency):\(ts)"
                neededHistoricalKeys.insert(cacheKey)
                if historicalRates[cacheKey] == nil {
                    historicalKeysToFetch.insert("\(quote.currency)|\(preferredCurrency)|\(ts)")
                }
            }
        }

        // Evict historical rates no longer needed
        let staleHistKeys = Set(historicalRates.keys).subtracting(neededHistoricalKeys)
        for key in staleHistKeys { historicalRates.removeValue(forKey: key) }

        await withTaskGroup(of: Void.self) { group in
            for key in historicalKeysToFetch {
                let parts = key.split(separator: "|")
                guard parts.count == 3,
                      let ts = Int(parts[2])
                else { continue }
                let from = String(parts[0])
                let to = String(parts[1])
                group.addTask { [weak self] in
                    await self?.fetchHistoricalExchangeRate(from: from, to: to, dateTimestamp: ts)
                }
            }
        }
    }

    func rate(from currency: String, for purchaseDate: Date? = nil) -> Double {
        let preferred = StorageService.shared.preferredCurrency
        if currency == preferred { return 1.0 }
        if let date = purchaseDate {
            let dayStart = Calendar.current.startOfDay(for: date)
            let ts = Int(dayStart.timeIntervalSince1970)
            let key = "\(currency)\(preferred):\(ts)"
            if let historical = historicalRates[key] { return historical }
        }
        return exchangeRates["\(currency)\(preferred)"] ?? 1.0
    }

    func priceRate(from currency: String) -> Double {
        priceDisplay(for: currency).rate
    }

    /// How to render a price quoted in `currency`: the multiplier, and the
    /// currency the result is actually in.
    ///
    /// #24: the rate and the symbol have to be decided together. While the FX
    /// pair is still loading (right after switching currency in Settings, when
    /// `exchangeRates` was just cleared, or when the fetch failed) there is no
    /// rate, and multiplying by a silent 1.0 printed the native figure under the
    /// target currency's symbol — a $190 stock reading "€190". Degrading to the
    /// stock's own currency keeps the number and the symbol in agreement; the
    /// display switches over on its own once the rate lands.
    func priceDisplay(for currency: String) -> (rate: Double, currency: String) {
        let target = StorageService.shared.stockPriceCurrency
        guard !target.isEmpty, target != currency else { return (1.0, currency) }
        guard let rate = exchangeRates["\(currency)\(target)"] else { return (1.0, currency) }
        return (rate, target)
    }

    /// #24: a currency switch clears `exchangeRates` and refetches, so a single
    /// dropped request left every converted figure stranded until the next poll
    /// minutes later. One retry covers the transient failure.
    private func fetchExchangeRate(from: String, to: String) async {
        let symbol = "\(from)\(to)=X"
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=1d") else { return }

        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            do {
                let (data, _) = try await session.data(from: url)
                let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
                if let result = response.chart.result?.first {
                    exchangeRates["\(from)\(to)"] = result.meta.regularMarketPrice
                    return
                }
            } catch {
            }
        }
    }

    private func fetchHistoricalExchangeRate(from: String, to: String, dateTimestamp: Int) async {
        let symbol = "\(from)\(to)=X"
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let period1 = dateTimestamp
        let period2 = dateTimestamp + 86400
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&period1=\(period1)&period2=\(period2)") else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(YahooChartResponse.self, from: data)
            guard let result = response.chart.result?.first,
                  let closes = result.indicators?.quote?.first?.close,
                  !closes.isEmpty
            else { return }
            let validCloses = closes.compactMap { $0 }
            guard let rate = validCloses.first else { return }
            historicalRates["\(from)\(to):\(dateTimestamp)"] = rate
        } catch {
        }
    }

    /// Ensures historical rate is loaded for a holding (e.g. when opening edit view)
    func ensureHistoricalRate(for holding: Holding) async {
        guard let purchaseDate = holding.purchaseDate,
              let quote = quotes[holding.symbol],
              quote.currency != StorageService.shared.preferredCurrency
        else { return }
        let dayStart = Calendar.current.startOfDay(for: purchaseDate)
        let ts = Int(dayStart.timeIntervalSince1970)
        let key = "\(quote.currency)\(StorageService.shared.preferredCurrency):\(ts)"
        guard historicalRates[key] == nil else { return }
        await fetchHistoricalExchangeRate(from: quote.currency, to: StorageService.shared.preferredCurrency, dateTimestamp: ts)
    }
}
