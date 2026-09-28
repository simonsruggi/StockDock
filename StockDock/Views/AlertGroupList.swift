import SwiftUI

/// Price alerts grouped by symbol, then by condition (Above / Below …). A level
/// only gets a disclosure chevron when it holds more than one alert.
struct AlertGroupList: View {
    @EnvironmentObject var storageService: StorageService
    @EnvironmentObject var stockService: StockService
    @State private var expanded: Set<String> = []
    @State private var sheet: AlertEditTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(PriceAlert.groupedBySymbol(storageService.alerts), id: \.symbol) { group in
                if group.alerts.count == 1, let alert = group.alerts.first {
                    AlertRow(alert: alert, showsSymbol: true)
                } else {
                    DisclosureHeader(key: group.symbol, alerts: group.alerts, expanded: $expanded) {
                        Text(group.symbol)
                            .font(.inter(12, weight: .semibold, relativeTo: .body))
                    }
                    if expanded.contains(group.symbol) {
                        conditionGroups(symbol: group.symbol, alerts: group.alerts)
                            .padding(.leading, 22)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .environment(\.editAlert) { alert, duplicate in
            sheet = AlertEditTarget(alert: alert, duplicate: duplicate)
        }
        .sheet(item: $sheet) { t in
            PriceAlertSheet(symbol: t.alert.symbol,
                            mode: t.duplicate ? .duplicate(t.alert) : .edit(t.alert)) { sheet = nil }
                .environmentObject(stockService).environmentObject(storageService)
        }
    }

    @ViewBuilder
    private func conditionGroups(symbol: String, alerts: [PriceAlert]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(PriceAlert.groupedByCondition(alerts), id: \.condition) { sub in
                let key = "\(symbol)|\(sub.condition.rawValue)"
                if sub.alerts.count == 1, let alert = sub.alerts.first {
                    AlertRow(alert: alert)
                } else {
                    DisclosureHeader(key: key, alerts: sub.alerts, expanded: $expanded,
                                     showsGroupToggle: true) {
                        HStack(spacing: 6) {
                            Image(systemName: sub.condition.systemImage)
                                .font(.inter(10, relativeTo: .caption))
                                .foregroundColor(.accentColor)
                            Text(sub.condition.shortLabel)
                                .font(.inter(11, weight: .medium, relativeTo: .caption))
                        }
                    }
                    if expanded.contains(key) {
                        ForEach(sub.alerts) { alert in
                            AlertRow(alert: alert).padding(.leading, 22)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }
}

private struct AlertEditTarget: Identifiable {
    let id = UUID()
    let alert: PriceAlert
    let duplicate: Bool
}

private struct EditAlertKey: EnvironmentKey {
    static let defaultValue: ((PriceAlert, Bool) -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens the alert editor: `(alert, duplicate)`. Nil outside `AlertGroupList`.
    var editAlert: ((PriceAlert, Bool) -> Void)? {
        get { self[EditAlertKey.self] }
        set { self[EditAlertKey.self] = newValue }
    }
}
