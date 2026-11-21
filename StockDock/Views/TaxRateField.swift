import SwiftUI

/// Percentage field for the capital-gains tax rate, styled like the DS pickers.
struct TaxRateField: View {
    @Binding var rate: Double
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            TextField("0", value: $rate, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(DS.figure)
                .foregroundStyle(DS.ink)
                .focused($focused)
                .frame(width: 40)
            Text("%").font(DS.body).foregroundStyle(DS.inkTertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.cardAlt))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(focused ? DS.brand : DS.hairline, lineWidth: focused ? 1.5 : 1))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
