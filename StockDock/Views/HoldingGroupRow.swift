import SwiftUI

/// A position in the popover: one row per symbol; clicking it shows its lots.
struct HoldingGroupRow: View {
    let lots: [Holding]
    let portfolioId: UUID
    @State private var expanded = false

    var body: some View {
        if lots.count == 1 {
            HoldingRow(holding: lots[0], portfolioId: portfolioId)
        } else {
            VStack(spacing: 0) {
                HoldingRow(holding: lots[0], portfolioId: portfolioId, lots: lots, expanded: expanded)
                    .contentShape(Rectangle())
                    // No animated insertion: inside a List it slides the lots over each other.
                    .onTapGesture { expanded.toggle() }
                if expanded {
                    ForEach(lots) { lot in
                        HoldingRow(holding: lot, portfolioId: portfolioId, isLot: true)
                            .padding(.leading, 12)
                    }
                }
            }
        }
    }
}
