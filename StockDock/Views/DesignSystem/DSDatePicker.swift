import SwiftUI

/// A DS-styled date field that opens a fully custom month calendar (no system
/// graphical picker, which clashes with the aesthetic). The date is optional:
/// an unset field stays unset until a day is picked, and can be cleared.
struct DSDatePicker: View {
    @Binding var date: Date?
    @State private var showCalendar = false
    /// Popovers don't inherit the window's locale, so the in-app language is passed in.
    @Environment(\.locale) private var locale

    private var calendarDate: Binding<Date> {
        Binding(get: { date ?? Date() }, set: { date = Calendar.current.startOfDay(for: $0) })
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let date {
                    Text(date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(DS.ink)
                } else {
                    Text("Not set").foregroundStyle(DS.inkTertiary)
                }
            }
            .font(DS.body)
            Spacer()
            if date != nil {
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(DS.inkTertiary)
                }
                .buttonStyle(.plain)
                .help(Text("Clear date"))
            }
            Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(DS.inkSecondary)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.cardAlt))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(showCalendar ? DS.brand : DS.hairline, lineWidth: showCalendar ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { showCalendar.toggle() }
        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
            DSCalendar(date: calendarDate) { showCalendar = false }
                .padding(14)
                .frame(width: 268)
                .background(DS.card)
                .environment(\.locale, locale)
        }
    }
}
