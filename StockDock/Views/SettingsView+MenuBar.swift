import SwiftUI

extension SettingsView {
    private var isTickerMode: Bool {
        storageService.menuBarDisplay == "ticker" || storageService.menuBarDisplay == "tickerPortfolio"
    }

    var menuBarGroup: some View {
        SettingsGroup(title: "Menu Bar", icon: "menubar.rectangle", isExpanded: $groupMenuBar) {
            SettingRow("Display") {
                DSPicker(options: [
                    ("pnl", "P&L (+321.09€)"),
                    ("dailyPnl", "Daily P&L (+321.09€)"),
                    ("pnlPercent", "P&L % (+2.3%)"),
                    ("pnlFull", "P&L + %"),
                    ("totalValue", "Total value"),
                    ("bestStock", "Best stock"),
                    ("worstStock", "Worst stock"),
                    ("bestWorst", "Best & Worst"),
                    ("portfolioRecap", "Portfolio recap"),
                    ("ticker", "Ticker (cycle watchlist)"),
                    ("tickerPortfolio", "Ticker + Portfolio"),
                    ("icon", "Icon only"),
                ], selection: $storageService.menuBarDisplay, width: 220)
            }
            .searchAnchor("menuBarDisplay")
            if isTickerMode {
                SettingDivider()
                SettingToggle("Show name instead of symbol", isOn: $storageService.tickerShowName).searchAnchor("tickerName")
                SettingDivider()
                SettingRow("Ticker order") {
                    DSPicker(options: [("manual", "As added"), ("type", "By type"), ("alpha", "Alphabetical")],
                             selection: $storageService.watchlistSort, width: 160)
                }
                .searchAnchor("tickerOrder")
            }
            SettingDivider()
            SettingToggle("Hide percentage change", isOn: $storageService.menuBarHidePercent).searchAnchor("hidePercent")
            SettingDivider()
            SettingToggle("Use system color in the menu bar", isOn: $storageService.menuBarUseSystemColor).searchAnchor("systemColor")

            SettingSubheader("Numbers")
            SettingRow("Percentage decimals") {
                DSPicker(options: [(0, "0"), (1, "1"), (2, "2"), (3, "3"), (4, "4")],
                         selection: $storageService.percentDecimals, width: 90)
            }
            .searchAnchor("percentDecimals")
            SettingDivider()
            SettingRow("Value decimals") {
                DSPicker(options: [(-1, "Auto"), (0, "0"), (1, "1"), (2, "2"), (3, "3"), (4, "4")],
                         selection: $storageService.valueDecimals, width: 90)
            }
            .searchAnchor("valueDecimals")

            SettingSubheader("Colors")
            SettingRow("Gain color") {
                DSColorWell(color: Binding(get: { Color(nsColor: storageService.gainColor) },
                                           set: { storageService.gainColorHex = $0.hexString }))
            }
            .searchAnchor("gainColor")
            SettingDivider()
            SettingRow("Loss color") {
                DSColorWell(color: Binding(get: { Color(nsColor: storageService.lossColor) },
                                           set: { storageService.lossColorHex = $0.hexString }))
            }
            .searchAnchor("lossColor")
            HStack {
                Spacer()
                SettingLinkButton("Reset to default green/red",
                                  enabled: !storageService.gainColorHex.isEmpty || !storageService.lossColorHex.isEmpty) {
                    storageService.gainColorHex = ""
                    storageService.lossColorHex = ""
                }
            }
            .padding(.vertical, 8)
        }
    }
}
