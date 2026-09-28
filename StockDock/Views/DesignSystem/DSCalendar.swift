import SwiftUI

/// A hand-built month calendar in the design system: emerald selection, warm
/// neutrals, Monday-first grid.
struct DSCalendar: View {
    @Binding var date: Date
    let onPick: () -> Void

    @State private var month: Date = Date()
    private let cal = Calendar.current

    private var weekdaySymbols: [String] {
        // Monday-first ordering of the locale's very-short weekday symbols.
        let syms = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(syms[first...] + syms[..<first])
    }

    /// Day cells for the visible month, with leading blanks for alignment.
    private var cells: [Date?] {
        guard let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else { return [] }
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth) // 1=Sun…7=Sat
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            out.append(cal.date(byAdding: .day, value: day - 1, to: firstOfMonth))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.inter(13, weight: .semibold, relativeTo: .body)).foregroundStyle(DS.ink)
                Spacer()
                stepButton("chevron.left") { shift(-1) }
                stepButton("chevron.right") { shift(1) }
            }
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s).font(DS.micro).foregroundStyle(DS.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 30) }
                }
            }
        }
        .onAppear { month = date }
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.inkSecondary).frame(width: 24, height: 24)
                .background(Circle().fill(DS.cardAlt))
        }.buttonStyle(.plain)
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: date)
        let isToday = cal.isDateInToday(day)
        return Button {
            date = day
            onPick()
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.inter(12, weight: selected ? .bold : .regular, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(selected ? .white : DS.ink)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(selected ? DS.brand : .clear)
                )
                .overlay(
                    Circle().strokeBorder(isToday && !selected ? DS.brand.opacity(0.5) : .clear, lineWidth: 1)
                )
        }.buttonStyle(.plain)
    }

    private func shift(_ months: Int) {
        if let m = cal.date(byAdding: .month, value: months, to: month) { month = m }
    }
}
