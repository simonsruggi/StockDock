import SwiftUI

/// One switch for every price alert: off disables them all, on re-arms them all
/// (triggered ones included).
struct AllAlertsToggle: View {
    @EnvironmentObject var storageService: StorageService

    private var allEnabled: Bool { storageService.alerts.allSatisfy(\.isEnabled) }

    var body: some View {
        SettingRow("All alerts") {
            DSToggle(isOn: Binding(
                get: { allEnabled },
                set: { storageService.setAlertsEnabled(ids: Set(storageService.alerts.map(\.id)), enabled: $0) }
            ))
            .help(allEnabled ? "Disable all" : "Re-arm all")
        }
    }
}
