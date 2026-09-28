import SwiftUI

struct TickerChipWide: View {
    let text: String; let emphasized: Bool
    var body: some View {
        Text(text).font(DS.micro)
            .foregroundStyle(emphasized ? Color.white : DS.brand)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(emphasized ? DS.brand : DS.brand.opacity(0.10)))
    }
}
