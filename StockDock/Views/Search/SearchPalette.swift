import SwiftUI

/// Desktop command palette (⌘K): a dimmed window with a centered search card.
struct SearchPalette: View {
    @ObservedObject var model: UniversalSearchModel
    @Binding var isPresented: Bool
    @FocusState private var focused: Bool
    @ObservedObject private var router = SearchRouter.shared

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                UniversalSearchField(model: model, focused: $focused, large: true) { close() }
                Divider().overlay(DS.hairline)
                SearchResultsList(model: model)
                    .frame(maxHeight: 420)
                Divider().overlay(DS.hairline)
                footer
            }
            .frame(width: 580)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DS.hairline))
            .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onChange(of: router.request) { _, request in
            if request?.surface == .window { isPresented = false }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", "Navigate")
            hint("↩", "Open")
            hint("esc", "Close")
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: key)
                .font(.inter(10, weight: .semibold, relativeTo: .caption2))
                .foregroundStyle(DS.inkSecondary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(DS.cardAlt))
            Text(LocalizedStringKey(label)).font(DS.micro).foregroundStyle(DS.inkTertiary)
        }
    }

    private func close() {
        model.reset()
        isPresented = false
    }
}
