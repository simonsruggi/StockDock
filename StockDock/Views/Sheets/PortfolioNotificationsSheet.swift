import SwiftUI

/// DS-styled create/manage sheet for a portfolio's recurring notifications.
struct PortfolioNotificationsSheet: View {
    @EnvironmentObject var storageService: StorageService
    let portfolioId: UUID
    let portfolioName: String
    let onDismiss: () -> Void

    @State private var newMode: PortfolioNotificationMode = .dailyPercent
    @State private var thresholdText = ""

    private var currencySymbol: String { StorageService.currencySymbol(for: storageService.preferredCurrency) }
    private var existing: [PortfolioNotification] { storageService.notifications(for: portfolioId) }
    private var thresholdUnit: String {
        switch newMode.thresholdKind {
        case .percent: return "%"
        case .currency: return currencySymbol
        case .hour: return "h"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Notifications · \(portfolioName)").font(DS.titleXL).tracking(-0.3).foregroundStyle(DS.ink)
                Spacer()
                Button("Done", action: onDismiss).buttonStyle(.plain)
                    .font(.inter(12, weight: .semibold, relativeTo: .body)).foregroundStyle(DS.brand)
                    .keyboardShortcut(.cancelAction)
            }

            if !existing.isEmpty {
                VStack(spacing: 0) {
                    ForEach(existing) { n in
                        HStack(spacing: 10) {
                            Image(systemName: n.mode.systemImage).font(.system(size: 12))
                                .foregroundStyle(n.isEnabled ? DS.brand : DS.inkTertiary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.mode.label).font(DS.bodyStrong).foregroundStyle(DS.ink)
                                Text(describe(n)).font(DS.micro).foregroundStyle(DS.inkTertiary)
                            }
                            Spacer()
                            DSToggle(isOn: Binding(
                                get: { n.isEnabled },
                                set: { storageService.setPortfolioNotificationEnabled(id: n.id, in: portfolioId, enabled: $0) }))
                            Button { storageService.removePortfolioNotification(id: n.id, from: portfolioId) } label: {
                                Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(DS.inkTertiary)
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        if n.id != existing.last?.id { Divider().overlay(DS.hairline.opacity(0.6)) }
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Add notification")
                DSPicker(options: PortfolioNotificationMode.allCases.map { ($0, $0.label) },
                         selection: $newMode, width: 240)
                    .onChange(of: newMode) { prefill() }
                Text(newMode.help).font(DS.caption).foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(LocalizedStringKey(thresholdFieldLabel)).font(DS.caption).foregroundStyle(DS.inkSecondary)
                    DSTextField(placeholder: placeholder, text: $thresholdText, mono: true).frame(width: 110)
                    Text(thresholdUnit).font(DS.body).foregroundStyle(DS.inkSecondary)
                    Spacer()
                }
                PrimaryButton(title: "Add", enabled: (parsed ?? 0) > 0, action: add)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.cardAlt))

            if !storageService.discordEnabled {
                Text("Tip: enable the Discord/Slack webhook in Settings to also receive these on your phone.")
                    .font(DS.micro).foregroundStyle(DS.inkTertiary)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(DS.ground)
        .onAppear(perform: prefill)
    }

    private var parsed: Double? { Double(thresholdText.replacingOccurrences(of: ",", with: ".")) }
    private var thresholdFieldLabel: String {
        switch newMode.thresholdKind {
        case .percent: return "Step"
        case .currency: return newMode == .milestone ? "Every" : "Step"
        case .hour: return "After"
        }
    }
    private var placeholder: String {
        switch newMode.thresholdKind {
        case .percent: return "1"
        case .currency: return newMode == .milestone ? "10000" : "250"
        case .hour: return "22"
        }
    }
    private func prefill() {
        thresholdText = (newMode.thresholdKind == .currency || newMode.thresholdKind == .hour)
            ? String(format: "%.0f", newMode.defaultThreshold)
            : String(format: "%g", newMode.defaultThreshold)
    }
    private func add() {
        guard let v = parsed, v > 0 else { return }
        storageService.addPortfolioNotification(PortfolioNotification(mode: newMode, threshold: v), to: portfolioId)
        prefill()
    }
    private func describe(_ n: PortfolioNotification) -> String {
        switch n.mode {
        case .dailyPercent: return "Every ±\(String(format: "%g", n.threshold))% move today"
        case .dailyAbsolute: return "Every ±\(currencySymbol)\(String(format: "%g", n.threshold)) move today"
        case .milestone: return "Every \(currencySymbol)\(String(format: "%g", n.threshold)) crossed"
        case .dailySummary: return "Daily after \(String(format: "%.0f", n.threshold)):00"
        }
    }
}
