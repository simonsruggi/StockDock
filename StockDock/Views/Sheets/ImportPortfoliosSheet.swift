import SwiftUI

/// Shown after picking an export file: the user ticks which portfolios to bring
/// in and decides whether the ones already in the app stay or are replaced.
struct ImportPortfoliosSheet: View {
    @EnvironmentObject var storageService: StorageService
    let candidates: [Portfolio]
    var width: CGFloat = 460
    let onDone: (_ importedCount: Int?) -> Void

    @State private var selected: Set<UUID>
    @State private var replaceExisting = false
    @State private var confirmReplace = false

    init(candidates: [Portfolio], width: CGFloat = 460, onDone: @escaping (_ importedCount: Int?) -> Void) {
        self.candidates = candidates
        self.width = width
        self.onDone = onDone
        _selected = State(initialValue: Set(candidates.map(\.id)))
    }

    var body: some View {
        SheetShell(title: "Import Portfolios", onCancel: { onDone(nil) }, width: width) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel("Portfolios in file")
                    Spacer()
                    Toggle("Select all", isOn: allSelected)
                        .toggleStyle(.checkbox)
                        .font(.inter(11.5, relativeTo: .caption))
                }
                candidateTable
            }
            if !storageService.portfolios.isEmpty {
                FieldBlock("Current portfolios") {
                    Picker("", selection: $replaceExisting) {
                        Text("Keep them").tag(false)
                        Text("Delete them and keep only the imported ones").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .font(DS.body)
                }
            }
            PrimaryButton(title: "Import", enabled: !selected.isEmpty) {
                if replaceExisting { confirmReplace = true } else { apply() }
            }
        }
        .dsAlert($confirmReplace, title: "Replace portfolios",
                 message: "Your current portfolios, with their notifications and history, will be deleted. This cannot be undone.",
                 confirmTitle: "Replace", destructive: true, onConfirm: apply)
    }

    private var candidateTable: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, portfolio in
                    if index > 0 { Divider().overlay(DS.hairline) }
                    candidateRow(portfolio)
                }
            }
        }
        .frame(maxHeight: 260)
        .fixedSize(horizontal: false, vertical: candidates.count <= 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DS.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline))
    }

    private func candidateRow(_ portfolio: Portfolio) -> some View {
        Toggle(isOn: Binding(
            get: { selected.contains(portfolio.id) },
            set: { if $0 { selected.insert(portfolio.id) } else { selected.remove(portfolio.id) } }
        )) {
            HStack {
                Text(portfolio.name)
                    .font(DS.bodyStrong).foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer()
                Text("\(portfolio.holdings.count) holdings")
                    .font(.inter(11.5, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(DS.inkSecondary)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var allSelected: Binding<Bool> {
        Binding(
            get: { selected.count == candidates.count },
            set: { selected = $0 ? Set(candidates.map(\.id)) : [] }
        )
    }

    private func apply() {
        let count = selected.count
        storageService.applyImport(candidates, selected: selected, replaceExisting: replaceExisting)
        onDone(count)
    }
}
