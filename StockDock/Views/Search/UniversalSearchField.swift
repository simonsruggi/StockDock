import SwiftUI

/// The search box: magnifier, field, clear button. Arrows move the selection,
/// Return opens it, Esc clears (or closes, via `onEscape`).
struct UniversalSearchField: View {
    @ObservedObject var model: UniversalSearchModel
    var focused: FocusState<Bool>.Binding
    var large = false
    var onEscape: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: large ? 14 : 11, weight: .medium))
                .foregroundStyle(DS.inkTertiary)
            TextField("Search stocks, portfolios, settings…", text: $model.query)
                .textFieldStyle(.plain)
                .font(large ? .inter(16, relativeTo: .title3) : DS.body)
                .foregroundStyle(DS.ink)
                .focused(focused)
                .onSubmit { model.activate() }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.escape) {
                    if let onEscape { onEscape() } else if !model.query.isEmpty { model.reset() } else { focused.wrappedValue = false }
                    return .handled
                }
            if model.isSearchingMarket {
                ProgressView().controlSize(.mini)
            }
            if !model.query.isEmpty {
                Button { model.reset() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: large ? 14 : 12))
                        .foregroundStyle(DS.inkTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, large ? 14 : 10)
        .padding(.vertical, large ? 12 : 7)
        .background(RoundedRectangle(cornerRadius: large ? 12 : 8, style: .continuous).fill(large ? DS.card : DS.cardAlt))
        .overlay(RoundedRectangle(cornerRadius: large ? 12 : 8, style: .continuous)
            .strokeBorder(focused.wrappedValue && !large ? DS.brand : DS.hairline, lineWidth: focused.wrappedValue && !large ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: focused.wrappedValue)
    }
}
