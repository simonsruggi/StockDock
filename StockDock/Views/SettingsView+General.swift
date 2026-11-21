import SwiftUI

extension SettingsView {
    var generalGroup: some View {
        SettingsGroup(title: "General", icon: "gearshape", isExpanded: $groupGeneral) {
            SettingRow("Language") {
                DSPicker(options: StorageService.supportedLanguages.map { ($0.code, $0.name) },
                         selection: $storageService.appLanguage, width: 180)
            }
            .searchAnchor("language")
            SettingDivider()
            SettingRow("Theme") {
                DSPicker(options: AppearanceMode.allCases.map { ($0, $0.label) },
                         selection: Binding(get: { storageService.appearanceMode },
                                            set: { storageService.appearanceMode = $0 }),
                         width: 140)
            }
            .searchAnchor("theme")
            SettingDivider()
            SettingRow("Font") {
                DSPicker(options: FontRegistration.availableFonts.map { ($0.family, $0.label) },
                         selection: $storageService.fontFamily, width: 180)
            }
            .searchAnchor("font")
            SettingDivider()
            SettingRow("Text size") {
                HStack(spacing: 8) {
                    Text("A").font(.inter(10, relativeTo: .caption)).foregroundStyle(DS.inkTertiary)
                    DSSlider(value: Binding(get: { Double(storageService.fontSizeLevel) },
                                            set: { storageService.fontSizeLevel = Int($0) }),
                             range: 7...13, step: 1, width: 96)
                    Text("A").font(.inter(14, weight: .bold, relativeTo: .body)).foregroundStyle(DS.inkTertiary)
                    Text("\(storageService.fontSizeLevel)")
                        .font(DS.figure).foregroundStyle(DS.inkSecondary)
                        .lineLimit(1)
                        .frame(width: 20, alignment: .trailing)
                }
                .fixedSize()
            }
            .searchAnchor("textSize")
            SettingDivider()
            SettingToggle("Show News tab", isOn: $storageService.showNewsTab).searchAnchor("newsTab")
        }
    }

    var currencyGroup: some View {
        SettingsGroup(title: "Currency", icon: "eurosign.circle", isExpanded: $groupCurrency) {
            SettingRow("Stock price currency") {
                DSPicker(options: Self.currencyOptions(withOriginal: true),
                         selection: $storageService.stockPriceCurrency, width: 160)
                    .onChange(of: storageService.stockPriceCurrency) { refreshRates() }
            }
            .searchAnchor("priceCurrency")
            SettingDivider()
            SettingRow("Portfolio currency") {
                DSPicker(options: Self.currencyOptions(withOriginal: false),
                         selection: $storageService.preferredCurrency, width: 160)
                    .onChange(of: storageService.preferredCurrency) { refreshRates() }
            }
            .searchAnchor("portfolioCurrency")
        }
    }
}
