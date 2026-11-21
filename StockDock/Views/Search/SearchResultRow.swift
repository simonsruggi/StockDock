import SwiftUI

/// One result: icon tile, title, subtitle, and on the selected row the key that opens it.
struct SearchResultRow: View {
    let item: SearchItem
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(item.section == .market ? DS.brand : DS.inkSecondary)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.cardAlt))
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(DS.bodyStrong)
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(subtitleKey)
                            .font(DS.caption)
                            .foregroundStyle(DS.inkTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.inkTertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? DS.brand.opacity(0.10) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var title: some View {
        if item.localizedTitle { Text(LocalizedStringKey(item.title)) } else { Text(verbatim: item.title) }
    }

    /// Settings show their category name, which is a localization key too.
    private var subtitleKey: LocalizedStringKey {
        item.section == .settings ? LocalizedStringKey(item.subtitle) : LocalizedStringKey(stringLiteral: item.subtitle)
    }
}
