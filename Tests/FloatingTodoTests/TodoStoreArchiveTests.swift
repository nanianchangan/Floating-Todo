import Foundation
import Testing
@testable import FloatingTodo

// Swift Testing 对每个 @Test 新建实例：init 建独立临时目录，deinit 清理
final class TodoStoreArchiveTests {
    private let directoryURL: URL
    private let fileURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        fileURL = directoryURL.appendingPathComponent("items.json")
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test func restoreArchivedClearsCompletionAndInsertsByOriginalCreationDate() throws {
        let newest = makeItem("较新待办", createdAt: date(2026, 8, 18), completedAt: nil)
        let restored = makeItem(
            "恢复条目",
            createdAt: date(2026, 8, 17),
            completedAt: date(2026, 8, 17, hour: 18)
        )
        let oldest = makeItem("较早待办", createdAt: date(2026, 8, 16), completedAt: nil)
        try writeFixture(items: [newest, oldest], archive: [restored])
        let store = TodoStore(fileURL: fileURL)

        store.restoreArchived(restored)

        #expect(store.archive.isEmpty)
        #expect(store.items.map(\.text) == ["较新待办", "恢复条目", "较早待办"])
        #expect(store.items[1].completedAt == nil)
        #expect(store.items[1].createdAt == restored.createdAt)

        let reloaded = TodoStore(fileURL: fileURL)
        #expect(reloaded.archive.isEmpty)
        #expect(reloaded.items.map(\.text) == ["较新待办", "恢复条目", "较早待办"])
        #expect(reloaded.items[1].completedAt == nil)
    }

    @Test func deleteArchivedRemovesOnlyTargetAndPersists() throws {
        let active = makeItem("待办", createdAt: date(2026, 8, 18), completedAt: nil)
        let deleted = makeItem(
            "删除目标",
            createdAt: date(2026, 8, 16),
            completedAt: date(2026, 8, 17, hour: 10)
        )
        let retained = makeItem(
            "保留记录",
            createdAt: date(2026, 8, 15),
            completedAt: date(2026, 8, 17, hour: 9)
        )
        try writeFixture(items: [active], archive: [deleted, retained])
        let store = TodoStore(fileURL: fileURL)

        store.deleteArchived(deleted)

        #expect(store.items == [active])
        #expect(store.archive == [retained])

        let reloaded = TodoStore(fileURL: fileURL)
        #expect(reloaded.items == [active])
        #expect(reloaded.archive == [retained])
    }

    private struct Fixture: Codable {
        let items: [TodoItem]
        let archive: [TodoItem]
    }

    private func writeFixture(items: [TodoItem], archive: [TodoItem]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Fixture(items: items, archive: archive)).write(to: fileURL)
    }

    private func makeItem(
        _ text: String,
        createdAt: Date,
        completedAt: Date?
    ) -> TodoItem {
        var item = TodoItem(text: text)
        item.createdAt = createdAt
        item.completedAt = completedAt
        return item
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
