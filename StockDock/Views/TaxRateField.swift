import SwiftUI

/// Percentage entry for the capital-gains tax rate (e.g. 26 for Italy).
struct TaxRateField: View {
    @Binding var rate: Double

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", value: $rate, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
            Text("%").foregroundStyle(.secondary)
        }
    }
}
