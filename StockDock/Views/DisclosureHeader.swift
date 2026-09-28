import SwiftUI

/// Chevron + title + count badge (+ triggered count); toggles `key` in `expanded`.
struct DisclosureHeader<Title: View>: View {
    @EnvironmentObject var storageService: StorageService
    let key: String
    let alerts: [PriceAlert]
    @Binding var expanded: Set<String>
    /// Master switch that enables/disables every alert in the group.
    var showsGroupToggle = false
    @ViewBuilder let title: () -> Title

    private var isExpanded: Bool { expanded.contains(key) }
    private var triggeredCount: Int { alerts.filter { !$0.isEnabled }.count }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded { expanded.remove(key) } else { expanded.insert(key) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.inter(9, weight: .semibold, relativeTo: .caption2))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14)
                title()
                Text("\(alerts.count)")
                    .font(.inter(9, weight: .semibold, relativeTo: .caption2))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Spacer()
                if triggeredCount > 0 {
                    Text("\(triggeredCount) triggered")
                        .font(.inter(8, weight: .semibold, relativeTo: .caption2))
                        .foregroundColor(.orange)
                }
                if showsGroupToggle {
                    Toggle("", isOn: Binding(
                        get: { triggeredCount == 0 },
                        set: { storageService.setAlertsEnabled(ids: Set(alerts.map(\.id)), enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help(triggeredCount == 0 ? "Disable all" : "Re-arm all")
                    // Keeps the switch aligned with the rows' switches (trash column).
                    Color.clear.frame(width: 14, height: 1)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
