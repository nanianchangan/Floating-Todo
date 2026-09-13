import Foundation
import Testing
@testable import FloatingTodo

final class TodoStoreReorderTests {
    private let directory: URL
    private let fileURL: URL
    private let store: TodoStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fileURL = directory.appendingPathComponent("items.json")
        store = TodoStore(fileURL: fileURL)
        for text in ["D", "C", "B", "A"] { store.add(text) }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    @Test(arguments: [
        (0, 2, false, ["B", "A", "C", "D"]),
        (0, 2, true, ["B", "C", "A", "D"]),
        (3, 1, false, ["A", "D", "B", "C"]),
        (3, 1, true, ["A", "B", "D", "C"]),
        (0, 3, true, ["B", "C", "D", "A"]),
        (3, 0, false, ["D", "A", "B", "C"])
    ])
    func movesAndPersists(_ example: (Int, Int, Bool, [String])) {
        let (source, target, after, expected) = example
        store.toggle(store.items[source])
        let original = store.items
        store.move(itemID: original[source].id, relativeTo: original[target].id, after: after)

        #expect(store.items.map(\.text) == expected)
        #expect(store.items.count == original.count)
        for item in original { #expect(store.items.first(where: { $0.id == item.id }) == item) }
        let reloaded = TodoStore(fileURL: fileURL)
        #expect(reloaded.items.map(\.id) == store.items.map(\.id))
        #expect(reloaded.items.map(\.text) == expected)
    }

    @Test func noOpAndInvalidMovesDoNotWrite() throws {
        let original = store.items
        let bytes = try Data(contentsOf: fileURL)
        store.move(itemID: original[1].id, relativeTo: original[1].id, after: false)
        store.move(itemID: original[1].id, relativeTo: original[1].id, after: true)
        store.move(itemID: original[1].id, relativeTo: original[2].id, after: false)
        store.move(itemID: original[1].id, relativeTo: original[0].id, after: true)
        store.move(itemID: UUID(), relativeTo: original[0].id, after: false)
        store.move(itemID: original[0].id, relativeTo: UUID(), after: true)
        #expect(store.items == original)
        #expect(try Data(contentsOf: fileURL) == bytes)
    }

    @Test func archivedSourceIsIgnoredAndNewItemsStillGoFirst() {
        let archived = store.items[1]
        store.toggle(archived)
        store.archiveItem(archived)
        let remaining = store.items
        store.move(itemID: archived.id, relativeTo: remaining[0].id, after: true)
        #expect(store.items == remaining)
        #expect(store.archive.map(\.id) == [archived.id])

        store.move(itemID: remaining[2].id, relativeTo: remaining[0].id, after: false)
        store.add("新条目")
        #expect(store.items.map(\.text) == ["新条目", "D", "A", "C"])
    }

    @Test func emptyAndSingleItemListsAreSafe() {
        for item in store.items { store.delete(item) }
        store.move(itemID: UUID(), relativeTo: UUID(), after: false)
        #expect(store.items.isEmpty)
        store.add("唯一一条")
        let item = store.items[0]
        store.move(itemID: item.id, relativeTo: item.id, after: true)
        #expect(store.items == [item])
    }
}
