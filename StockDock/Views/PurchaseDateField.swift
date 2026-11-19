import SwiftUI

/// Purchase date for the compact add/edit forms. A new lot starts undated:
/// defaulting to today would make a position held for years count as bought
/// today, and its whole gain would show up as today's P&L.
struct PurchaseDateField: View {
    @Binding var date: Date?

    private var pickerDate: Binding<Date> {
        Binding(get: { date ?? Date() }, set: { date = Calendar.current.startOfDay(for: $0) })
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Purchase date")
                .font(.inter(10, relativeTo: .caption))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                if date != nil {
                    DatePicker("", selection: pickerDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    Button { date = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Clear date"))
                } else {
                    Button("Set date") { date = Calendar.current.startOfDay(for: Date()) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}
