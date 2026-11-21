import SwiftUI

extension SettingsView {
    var positionsGroup: some View {
        SettingsGroup(title: "Positions & Market", icon: "chart.line.uptrend.xyaxis", isExpanded: $groupPositions) {
            SettingToggle("Short positions & leverage", isOn: $storageService.advancedPositions)
            SettingDivider()
            SettingRow("Tax on gains", caption: "P&L shown net of tax · 0 = gross") {
                TaxRateField(rate: $storageService.taxRate)
            }
            SettingDivider()
            SettingRow("Weights based on") {
                DSPicker(options: [("cost", "Cost basis"), ("value", "Market value")],
                         selection: $storageService.weightBasis, width: 160)
            }
            SettingDivider()
            SettingToggle("Extended hours (Pre/Post)", isOn: $storageService.showExtendedHours)
            if storageService.showExtendedHours {
                SettingDivider()
                SettingToggle("Overnight & weekends (Hyperliquid)",
                              caption: "Perpetual futures price when there is no Pre/Post session, not the official quote",
                              isOn: $storageService.showAllHoursPrices)
            }
        }
    }

    var watchlistGroup: some View {
        SettingsGroup(title: "Watchlist", icon: "list.bullet", isExpanded: $groupWatchlist) {
            SettingToggle("Company name", isOn: $storageService.showCompanyName)
            SettingDivider()
            SettingToggle("Day range (low – high)", isOn: $storageService.showDayRange)
            SettingDivider()
            SettingToggle("52-week range bar", isOn: $storageService.show52WeekBar)
            SettingDivider()
            SettingToggle("Absolute change value", isOn: $storageService.showAbsoluteChange)
        }
    }
}
