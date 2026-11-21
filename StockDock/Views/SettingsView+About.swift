import AppKit
import SwiftUI

extension SettingsView {
    var aboutGroup: some View {
        SettingsGroup(title: "About & Data", icon: "info.circle", isExpanded: $groupAbout) {
            SettingRow("Updates") {
                SettingLinkButton("Check for Updates…", enabled: updaterViewModel.canCheckForUpdates) {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    updaterViewModel.checkForUpdates()
                }
            }
            SettingDivider()
            SettingRow("Support StockDock") {
                HStack(spacing: 6) {
                    supportButton("Sponsor", icon: "heart.fill", color: Color(red: 0.86, green: 0.30, blue: 0.46),
                                  url: "https://github.com/sponsors/simonsruggi")
                    supportButton("Star", icon: "star.fill", color: Color(red: 0.92, green: 0.70, blue: 0.15),
                                  url: "https://github.com/simonsruggi/StockDock")
                }
                .fixedSize()
            }
            SettingDivider()
            SettingRow("Reset", caption: "Portfolios and watchlist are not affected") {
                SettingLinkButton("Reset to Defaults…", tint: DS.down) { showResetAlert = true }
            }
        }
    }

    private func supportButton(_ title: String, icon: String, color: Color, url: String) -> some View {
        Button {
            if let link = URL(string: url) { NSWorkspace.shared.open(link) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(LocalizedStringKey(title)).font(.inter(11.5, weight: .semibold, relativeTo: .caption)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color))
        }
        .buttonStyle(.plain)
    }
}
