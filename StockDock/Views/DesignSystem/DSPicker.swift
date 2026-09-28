import SwiftUI

/// A design-system select: a pill showing the current value that opens a DS
/// popover of options with a checkmark on the selection.
struct DSPicker<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var width: CGFloat = 240
    @State private var show = false

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 7) {
                Text(LocalizedStringKey(currentLabel)).font(DS.body).foregroundStyle(DS.ink).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(DS.inkTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.cardAlt))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(show ? DS.brand : DS.hairline, lineWidth: show ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(options, id: \.value) { opt in
                        DSPickerRow(label: opt.label, selected: opt.value == selection) {
                            selection = opt.value; show = false
                        }
                    }
                }
                .padding(6)
            }
            .frame(width: width)
            .frame(maxHeight: 320)
        }
    }
}

private struct DSPickerRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(LocalizedStringKey(label)).font(.inter(12.5, weight: selected ? .semibold : .regular, relativeTo: .body))
                    .foregroundStyle(DS.ink)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.brand) }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? DS.brand.opacity(0.10) : (selected ? DS.brand.opacity(0.06) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
