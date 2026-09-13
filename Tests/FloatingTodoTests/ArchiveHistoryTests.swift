import Foundation
import Testing
@testable import FloatingTodo

struct ArchiveHistoryTests {
    @Test func groupsByLocalDayAndSortsDaysAndItemsNewestFirst() {
        let calendar = makeCalendar(timeZone: "Asia/Shanghai")
        let older = makeItem("较早完成", completedAt: date(2026, 8, 17, 9, 0, calendar: calendar))
        let newer = makeItem("较晚完成", completedAt: date(2026, 8, 17, 18, 0, calendar: calendar))
        let latestDay = makeItem("次日完成", completedAt: date(2026, 8, 18, 8, 0, calendar: calendar))
        var incomplete = TodoItem(text: "未完成")
        incomplete.completedAt = nil

        let days = ArchiveHistory.days(
            from: [older, latestDay, incomplete, newer],
            calendar: calendar
        )

        #expect(days.count == 2)
        #expect(days[0].day == calendar.startOfDay(for: latestDay.completedAt!))
        #expect(days[0].items.map(\.text) == ["次日完成"])
        #expect(days[1].items.map(\.text) == ["较晚完成", "较早完成"])
    }

    @Test func usesCalendarTimeZoneAcrossMidnight() {
        let shanghai = makeCalendar(timeZone: "Asia/Shanghai")
        let utc = makeCalendar(timeZone: "UTC")
        let beforeLocalMidnight = makeItem(
            "午夜前",
            completedAt: date(2026, 8, 17, 23, 30, calendar: shanghai)
        )
        let afterLocalMidnight = makeItem(
            "午夜后",
            completedAt: date(2026, 8, 18, 0, 30, calendar: shanghai)
        )

        #expect(
            ArchiveHistory.days(from: [beforeLocalMidnight, afterLocalMidnight], calendar: shanghai).count
                == 2
        )
        #expect(
            ArchiveHistory.days(from: [beforeLocalMidnight, afterLocalMidnight], calendar: utc).count
                == 1
        )
    }

    @Test func selectionKeepsExistingDayAndFallsBackToLatest() {
        let calendar = makeCalendar(timeZone: "Asia/Shanghai")
        let latest = makeItem("最新", completedAt: date(2026, 8, 18, 8, 0, calendar: calendar))
        let older = makeItem("较早", completedAt: date(2026, 8, 16, 8, 0, calendar: calendar))
        let days = ArchiveHistory.days(from: [older, latest], calendar: calendar)

        #expect(ArchiveHistory.resolvedSelection(days[1].day, in: days) == days[1].day)
        #expect(ArchiveHistory.resolvedSelection(nil, in: days) == days[0].day)
        #expect(
            ArchiveHistory.resolvedSelection(date(2025, 1, 1, 0, 0, calendar: calendar), in: days)
                == days[0].day
        )
        #expect(ArchiveHistory.resolvedSelection(nil, in: []) == nil)
    }

    @Test func adjacentDayPrefersNewerThenOlder() {
        let calendar = makeCalendar(timeZone: "Asia/Shanghai")
        let days = ArchiveHistory.days(
            from: [
                makeItem("最新", completedAt: date(2026, 8, 18, 8, 0, calendar: calendar)),
                makeItem("中间", completedAt: date(2026, 8, 17, 8, 0, calendar: calendar)),
                makeItem("最早", completedAt: date(2026, 8, 16, 8, 0, calendar: calendar)),
            ],
            calendar: calendar
        )

        #expect(ArchiveHistory.adjacentDay(afterRemovingDayAt: 1, from: days) == days[0].day)
        #expect(ArchiveHistory.adjacentDay(afterRemovingDayAt: 0, from: days) == days[1].day)
        #expect(ArchiveHistory.adjacentDay(afterRemovingDayAt: 0, from: [days[0]]) == nil)
        #expect(ArchiveHistory.adjacentDay(afterRemovingDayAt: 3, from: days) == nil)
    }

    @Test func dateLabelOmitsCurrentYearAndIncludesDifferentYear() {
        let calendar = makeCalendar(timeZone: "Asia/Shanghai")
        let now = date(2026, 8, 18, 12, 0, calendar: calendar)

        #expect(
            ArchiveHistory.label(
                for: date(2026, 8, 17, 12, 0, calendar: calendar),
                relativeTo: now,
                calendar: calendar
            ) == "8月17日 周一"
        )
        #expect(
            ArchiveHistory.label(
                for: date(2025, 12, 31, 12, 0, calendar: calendar),
                relativeTo: now,
                calendar: calendar
            ) == "2025年12月31日 周三"
        )
    }

    private func makeCalendar(timeZone identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func makeItem(_ text: String, completedAt: Date) -> TodoItem {
        var item = TodoItem(text: text)
        item.completedAt = completedAt
        return item
    }
}
