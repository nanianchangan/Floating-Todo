import Foundation

struct ArchiveDay: Equatable {
    let day: Date
    let items: [TodoItem]
}

enum ArchiveHistory {
    static func days(
        from items: [TodoItem],
        calendar: Calendar = .current
    ) -> [ArchiveDay] {
        let grouped = Dictionary(grouping: items.compactMap { item -> (Date, TodoItem)? in
            guard let completedAt = item.completedAt else { return nil }
            return (calendar.startOfDay(for: completedAt), item)
        }, by: \.0)

        return grouped.map { day, entries in
            ArchiveDay(
                day: day,
                items: entries
                    .map(\.1)
                    .sorted {
                        ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
                    }
            )
        }
        .sorted { $0.day > $1.day }
    }

    static func resolvedSelection(_ selectedDay: Date?, in days: [ArchiveDay]) -> Date? {
        guard !days.isEmpty else { return nil }
        if let selectedDay, days.contains(where: { $0.day == selectedDay }) {
            return selectedDay
        }
        return days[0].day
    }

    /// 当前日期被移除后，优先选择相邻的更新日期，没有则选择更早日期。
    static func adjacentDay(afterRemovingDayAt index: Int, from days: [ArchiveDay]) -> Date? {
        guard days.indices.contains(index) else { return nil }
        if index > 0 {
            return days[index - 1].day
        }
        let olderIndex = index + 1
        return days.indices.contains(olderIndex) ? days[olderIndex].day : nil
    }

    /// 共享格式化器：DateFormatter 创建成本高，避免每次渲染都新建。
    /// 每次调用前会重设 calendar/timeZone/dateFormat，仅限主线程使用。
    private static let labelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    static func label(
        for day: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let formatter = labelFormatter
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.component(.year, from: day)
            == calendar.component(.year, from: now)
            ? "M月d日 EEE"
            : "yyyy年M月d日 EEE"
        return formatter.string(from: day)
    }
}
