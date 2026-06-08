import SwiftUI

/// Sheet for managing the recurring notifications attached to a single portfolio.
struct PortfolioNotificationsView: View {
    @EnvironmentObject var storageService: StorageService

    let portfolioId: UUID
    let portfolioName: String
    let onDismiss: () -> Void

    @State private var newMode: PortfolioNotificationMode = .dailyPercent
    @State private var thresholdText: String = ""

    private var currencySymbol: String {
        StorageService.currencySymbol(for: storageService.preferredCurrency)
    }

    private var existing: [PortfolioNotification] {
        storageService.notifications(for: portfolioId)
    }

    private var thresholdUnit: String {
        switch newMode.thresholdKind {
        case .percent: return "%"
        case .currency: return currencySymbol
        case .hour: return "h"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notifications — \(portfolioName)")
                    .font(.inter(13, weight: .bold, relativeTo: .headline))
                Spacer()
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderless)
            }

            if !existing.isEmpty {
                VStack(spacing: 4) {
                    ForEach(existing) { n in
                        HStack(spacing: 8) {
                            Image(systemName: n.mode.systemImage)
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.mode.label)
                                    .font(.inter(11, weight: .medium, relativeTo: .body))
                                Text(describe(n))
                                    .font(.inter(10, relativeTo: .caption))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { n.isEnabled },
                                set: { storageService.setPortfolioNotificationEnabled(id: n.id, in: portfolioId, enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            Button(action: { storageService.removePortfolioNotification(id: n.id, from: portfolioId) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Divider()
            }

            // Add new
            VStack(alignment: .leading, spacing: 4) {
                Text("Add notification")
                    .font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                Picker("Mode", selection: $newMode) {
                    ForEach(PortfolioNotificationMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: newMode) { prefillThreshold() }

                Text(newMode.help)
                    .font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(thresholdFieldLabel)
                        .font(.inter(10, relativeTo: .caption)).foregroundColor(.secondary)
                    TextField(placeholder, text: $thresholdText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text(thresholdUnit)
                        .font(.inter(11, relativeTo: .body)).foregroundColor(.secondary)
                }
            }

            Button("Add") {
                guard let value = parsedThreshold, value > 0 else { return }
                storageService.addPortfolioNotification(
                    PortfolioNotification(mode: newMode, threshold: value), to: portfolioId)
                prefillThreshold()
            }
            .buttonStyle(.borderedProminent)
            .disabled(parsedThreshold == nil || (parsedThreshold ?? 0) <= 0)

            if !storageService.discordEnabled {
                Text("Tip: enable the Discord/Slack webhook in Settings to also receive these on your phone.")
                    .font(.inter(9, relativeTo: .caption2)).foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 280)
        .onAppear { prefillThreshold() }
    }

    private var parsedThreshold: Double? {
        Double(thresholdText.replacingOccurrences(of: ",", with: "."))
    }

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

    private func prefillThreshold() {
        thresholdText = newMode.thresholdKind == .currency || newMode.thresholdKind == .hour
            ? String(format: "%.0f", newMode.defaultThreshold)
            : String(format: "%g", newMode.defaultThreshold)
    }

    private func describe(_ n: PortfolioNotification) -> String {
        switch n.mode {
        case .dailyPercent:
            return "Every ±\(String(format: "%g", n.threshold))% move today"
        case .dailyAbsolute:
            return "Every ±\(String(format: "%g", n.threshold))\(currencySymbol) move today"
        case .milestone:
            return "Every \(String(format: "%g", n.threshold))\(currencySymbol) crossed"
        case .dailySummary:
            return "Daily after \(String(format: "%.0f", n.threshold)):00"
        }
    }
}
