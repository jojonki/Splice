import SwiftUI

/// 開始日 → 終了日の順にタップして期間を選ぶカレンダー。撮影した日には点を表示する。
/// 最初は何も選ばれていない（start, end ともに nil）。
struct RangeCalendarView: View {
    /// nil の間は「開始日を選択中」
    @Binding var start: Date?
    /// nil の間は「終了日を選択中」
    @Binding var end: Date?

    @State private var month: Date
    @State private var counts: [Date: Int] = [:]

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: .now)

    init(start: Binding<Date?>, end: Binding<Date?>) {
        _start = start
        _end = end
        let month = Calendar.current.dateInterval(of: .month, for: (end.wrappedValue ?? start.wrappedValue ?? .now))?.start
        _month = State(initialValue: month ?? .now)
    }

    var body: some View {
        VStack(spacing: 12) {
            presets
            header
            weekdayRow
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 40) }
                }
            }
            summary
        }
        .task(id: month) {
            guard await PhotoLibrary.requestAccess(),
                  let interval = calendar.dateInterval(of: .month, for: month) else { return }
            counts = PhotoLibrary.dailyCounts(from: interval.start, to: interval.end)
        }
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                preset("今日", days: 1, endingDaysAgo: 0)
                preset("昨日", days: 1, endingDaysAgo: 1)
                preset("直近3日", days: 3, endingDaysAgo: 0)
                preset("直近7日", days: 7, endingDaysAgo: 0)
            }
        }
    }

    private func preset(_ title: LocalizedStringKey, days: Int, endingDaysAgo: Int) -> some View {
        Button(title) {
            let last = calendar.date(byAdding: .day, value: -endingDaysAgo, to: today) ?? today
            start = calendar.date(byAdding: .day, value: -(days - 1), to: last) ?? last
            end = last
            month = calendar.dateInterval(of: .month, for: last)?.start ?? month
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(month.formatted(inApp: .dateTime.year().month(.wide))).font(.headline)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .disabled(calendar.isDate(month, equalTo: today, toGranularity: .month))
        }
        .buttonStyle(.borderless)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { i, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(i == 0 ? .red : i == 6 ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// 月の1日の曜日に合わせて先頭を空ける
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading)
            + days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
    }

    private func dayCell(_ day: Date) -> some View {
        let isFuture = day > today
        let isStart = start.map { calendar.isDate(day, inSameDayAs: $0) } == true
        let isEnd = end.map { calendar.isDate(day, inSameDayAs: $0) } == true
        let isEdge = isStart || isEnd
        let inRange: Bool = {
            guard let start, let end else { return false }
            return day >= calendar.startOfDay(for: start) && day <= end
        }()
        let count = counts[day] ?? 0
        let band = Color.accentColor.opacity(0.15)

        return Button {
            select(day)
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.body.monospacedDigit())
                    .fontWeight(isEdge ? .bold : .regular)
                    .foregroundStyle(isEdge ? Color.white : isFuture ? Color.secondary.opacity(0.4) : .primary)
                    .frame(width: 34, height: 34)
                    .background(isEdge ? Circle().fill(Color.accentColor) : nil)
                    .frame(maxWidth: .infinity)
                    // 期間の帯。開始日は右半分、終了日は左半分だけ塗って丸とつなげる
                    .background {
                        HStack(spacing: 0) {
                            (inRange && !isStart ? band : .clear)
                            (inRange && !isEnd ? band : .clear)
                        }
                    }
                Circle()
                    .fill(Color.orange)
                    .opacity(count == 0 ? 0 : min(1, 0.35 + Double(count) / 30))
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private var summary: some View {
        HStack {
            if let start, let end {
                let days = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
                Text(L("%@ 〜 %@", format(start), format(end))).bold()
                Text(L("%lld日間", days)).foregroundStyle(.secondary)
            } else if let start {
                Text(L("%@ 〜", format(start))).bold()
                Text("終了日をタップ").foregroundStyle(.secondary)
            } else {
                Text("開始日をタップ").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.subheadline)
    }

    private func format(_ date: Date) -> String {
        date.formatted(inApp: .dateTime.month().day().weekday(.abbreviated))
    }

    /// 1回目のタップで開始日、2回目で終了日。開始日より前をタップしたら開始日を選び直す。
    private func select(_ day: Date) {
        if let start, end == nil, day >= start {
            end = day
        } else {
            start = day
            end = nil
        }
    }

    private func shiftMonth(_ value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: month) { month = next }
    }
}
