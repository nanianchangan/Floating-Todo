import Foundation
import Testing
@testable import FloatingTodo

final class TodoFocusTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var fileURL: URL { directory.appendingPathComponent("items.json") }
    private let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
    deinit { try? FileManager.default.removeItem(at: directory) }

    @Test func dailyResetPreservesUnfinishedTaskAndOrder() {
        var clock = today
        let store = TodoStore(fileURL: fileURL, now: { clock })
        store.add("重点")
        store.add("普通")
        let ids = store.items.map(\.id)
        store.toggleFocus(store.items[1])
        #expect(store.items[1].isFocused(on: clock))
        clock = Calendar.current.date(byAdding: .day, value: 1, to: clock)!
        store.archiveOldCompleted()
        #expect(store.items.map(\.id) == ids)
        #expect(store.items.allSatisfy { $0.focusDate == nil })
        #expect(store.archive.isEmpty)
        let reloaded = TodoStore(fileURL: fileURL, now: { clock })
        #expect(reloaded.items.map(\.id) == ids)
        #expect(reloaded.items.allSatisfy { $0.focusDate == nil && $0.completedAt == nil })
    }

    @Test func manualArchivePersistsStarAndRestoreResetsIt() {
        let store = TodoStore(fileURL: fileURL, now: { self.today })
        store.add("重点")
        store.toggleFocus(store.items[0])
        store.toggle(store.items[0])
        store.archiveItem(store.items[0])
        #expect(store.archive[0].archivedFocus == true)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let reloaded = TodoStore(fileURL: fileURL, now: { tomorrow })
        #expect(reloaded.archive[0].archivedFocus == true)
        reloaded.restoreArchived(reloaded.archive[0])
        #expect(reloaded.items[0].focusDate == nil)
        #expect(reloaded.items[0].archivedFocus == nil)
        #expect(reloaded.items[0].completedAt == nil)
    }

    @Test func automaticArchiveKeepsCompletedDayFocusAfterRelaunch() {
        let store = TodoStore(fileURL: fileURL, now: { self.today })
        store.add("重点")
        store.toggleFocus(store.items[0])
        store.toggle(store.items[0])
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let reloaded = TodoStore(fileURL: fileURL, now: { tomorrow })
        #expect(reloaded.items.isEmpty)
        #expect(reloaded.archive[0].archivedFocus == true)
    }

    @Test func bulkArchiveDistinguishesUnstarredAndCancelledFocus() {
        let store = TodoStore(fileURL: fileURL, now: { self.today })
        for text in ["普通", "取消", "重点"] { store.add(text) }
        store.toggleFocus(store.items[0])
        store.toggleFocus(store.items[1])
        store.toggleFocus(store.items[1])
        for item in store.items { store.toggle(item) }
        store.archiveCompleted()
        #expect(store.archive.map { $0.archivedFocus == true } == [true, false, false])
    }

    @Test func oldItemWithoutFocusFieldsStillDecodes() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","text":"旧任务","createdAt":0}
        """
        let item = try JSONDecoder().decode(TodoItem.self, from: Data(json.utf8))
        #expect(item.focusDate == nil)
        #expect(item.archivedFocus == nil)
    }
}
