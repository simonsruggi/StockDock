import Sparkle
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService
    @EnvironmentObject var updaterViewModel: UpdaterViewModel
    @State private var showResetAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Stock Price Currency
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stock Price Currency")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Picker("Price currency", selection: $storageService.stockPriceCurrency) {
                        Text("Original").tag("")
                        ForEach(StorageService.supportedCurrencies, id: \.self) { code in
                            Text("\(StorageService.currencySymbol(for: code)) \(code)")
                                .tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: storageService.stockPriceCurrency) {
                        stockService.exchangeRates.removeAll()
                        Task {
                            await stockService.refreshAll(storageService: storageService)
                        }
                    }
                    Text(storageService.stockPriceCurrency.isEmpty
                         ? "Prices shown in their native currency"
                         : "All prices converted to \(storageService.stockPriceCurrency)")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Portfolio Currency
                VStack(alignment: .leading, spacing: 6) {
                    Text("Portfolio Currency")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Picker("Portfolio currency", selection: $storageService.preferredCurrency) {
                        ForEach(StorageService.supportedCurrencies, id: \.self) { code in
                            Text("\(StorageService.currencySymbol(for: code)) \(code)")
                                .tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: storageService.preferredCurrency) {
                        stockService.exchangeRates.removeAll()
                        Task {
                            await stockService.refreshAll(storageService: storageService)
                        }
                    }
                    Text("Portfolio totals and P&L converted to \(storageService.preferredCurrency)")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Extended Hours
                VStack(alignment: .leading, spacing: 6) {
                    Text("Market Hours")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Toggle("Show extended hours (Pre/Post)", isOn: $storageService.showExtendedHours)
                        .toggleStyle(.switch)
                    Text("Show pre-market and after-hours prices")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Menu Bar Display
                VStack(alignment: .leading, spacing: 6) {
                    Text("Menu Bar Display")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Picker("Display", selection: $storageService.menuBarDisplay) {
                        Text("P&L (+321.09€)").tag("pnl")
                        Text("P&L % (+2.3%)").tag("pnlPercent")
                        Text("P&L + % (+321.09€ +2.3%)").tag("pnlFull")
                        Text("Total Value (14396.67€)").tag("totalValue")
                        Text("Best Stock (▲ AAPL +1.2%)").tag("bestStock")
                        Text("Worst Stock (▼ TSLA -0.8%)").tag("worstStock")
                        Text("Best & Worst").tag("bestWorst")
                        Text("Portfolio (14396.67€ +1.2%)").tag("portfolioRecap")
                        Text("Ticker (cycle watchlist)").tag("ticker")
                        Text("Icon Only").tag("icon")
                    }
                    .pickerStyle(.menu)
                    Text("Choose what to show in the menu bar")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }
                Divider()

                // MARK: - Font
                VStack(alignment: .leading, spacing: 6) {
                    Text("Font")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Picker("Font family", selection: $storageService.fontFamily) {
                        ForEach(FontRegistration.availableFonts, id: \.family) { font in
                            Text(font.label)
                                .font(.custom(font.family, size: 13))
                                .tag(font.family)
                        }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        Text("A")
                            .font(.inter(10, relativeTo: .caption))
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { Double(storageService.fontSizeLevel) },
                            set: { storageService.fontSizeLevel = Int($0) }
                        ), in: 7...13, step: 1)
                        Text("A")
                            .font(.inter(18, weight: .bold, relativeTo: .title2))
                            .foregroundColor(.secondary)
                    }
                    Text("Size: \(storageService.fontSizeLevel)")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Updates
                VStack(alignment: .leading, spacing: 6) {
                    Text("Updates")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Button("Check for Updates...") {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Reset")
                        .font(.inter(13, weight: .bold, relativeTo: .headline))
                    Button("Reset to Default Settings") {
                        showResetAlert = true
                    }
                    .foregroundColor(.red)
                    Text("This will not erase your portfolios or watchlist")
                        .font(.inter(10, relativeTo: .caption))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .alert("Reset Settings", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                storageService.resetToDefaults()
                Task {
                    stockService.exchangeRates.removeAll()
                    await stockService.refreshAll(storageService: storageService)
                }
            }
        } message: {
            Text("This will reset all settings to their defaults. Your portfolios and watchlist will not be affected.")
        }
    }

}
