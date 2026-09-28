import SwiftUI

/// The app's segmented range picker (1M / 3M / 6M / …): a white pill sliding
/// inside a warm capsule, with real hit targets. Shared by every chart so
/// period switching looks and feels the same everywhere.
struct SegmentedRangePicker<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    @Namespace private var ns

    private func help(_ label: String) -> String {
        switch label {
        case "24H": return "Last 24 hours"
        case "7D": return "Last 7 days"
        case "1M": return "Last month"
        case "1Y": return "Last year"
        case "All": return "All available history"
        default: return label
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.inter(10, weight: .semibold, relativeTo: .caption2))
                        .foregroundStyle(selection == option ? DS.ink : DS.inkTertiary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background {
                            if selection == option {
                                Capsule().fill(DS.card)
                                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "segSelection", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(help(label(option)))
            }
        }
        .padding(3)
        .background(Capsule().fill(DS.cardAlt))
    }
}
