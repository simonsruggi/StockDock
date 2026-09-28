import SwiftUI

/// A DS-styled date field that opens a fully custom month calendar (no system
/// graphical picker, which clashes with the aesthetic).
struct DSDatePicker: View {
    @Binding var date: Date
    @State private var showCalendar = false

    var body: some View {
        Button { showCalendar.toggle() } label: {
            HStack(spacing: 8) {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(DS.body).foregroundStyle(DS.ink)
                Spacer()
                Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(DS.inkSecondary)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.cardAlt))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(showCalendar ? DS.brand : DS.hairline, lineWidth: showCalendar ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
            DSCalendar(date: $date) { showCalendar = false }
                .padding(14)
                .frame(width: 268)
                .background(DS.card)
        }
    }
}
