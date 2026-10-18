import SwiftUI

/// The "24/7" tag on Hyperliquid prices: its own colour and an outline, so it
/// never reads as a Pre/Post session of the same market.
struct AllHoursBadge: View {
    var size: CGFloat = 9

    var body: some View {
        Text("24/7")
            .font(.inter(size, weight: .bold, relativeTo: .caption2))
            .foregroundStyle(DS.allHours)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(DS.allHours.opacity(0.7), lineWidth: 1))
            .help("Hyperliquid perpetual (trade.xyz), trades 24/7 — not the official exchange price")
    }
}
