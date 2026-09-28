import SwiftUI

/// A compact ticker pill shown next to a news story. The reference stock (the one
/// the story is about) is emphasized with a filled accent background; other
/// related tickers get a subtle tinted background.
struct TickerChip: View {
    let text: String
    let emphasized: Bool

    var body: some View {
        Text(text)
            .font(.inter(8, weight: .bold, relativeTo: .caption2))
            .foregroundColor(emphasized ? .white : DS.brand)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(emphasized ? DS.brand : DS.brand.opacity(0.12))
            )
    }
}
