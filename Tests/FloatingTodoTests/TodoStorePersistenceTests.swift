import Foundation
import Testing
@testable import FloatingTodo

// Swift Testing 对每个 @Test 新建实例：init 建独立临时目录，deinit 清理
final class TodoStorePersistenceTests {
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

    @Test func editedTextPersistsAndPreservesItemState() throws {
        let store = TodoStore(fileURL: fileURL)
        store.add("原内容")
        let item = try #require(store.items.first)
        store.toggleFocus(item)
        store.toggle(item)
        let before = try #require(TodoStore(fileURL: fileURL).items.first)
        store.updateText("  新内容  ", for: item.id)
        let reloaded = TodoStore(fileURL: fileURL)
        var expected = before
        expected.text = "新内容"
        #expect(reloaded.items == [expected])
        reloaded.updateText(" \n ", for: item.id)
        #expect(TodoStore(fileURL: fileURL).items == [expected])
    }

    @Test func corruptFileIsBackedUpBeforeAnySave() throws {
        let corruptContent = Data("{\"items\": [{\"broken".utf8)
        try corruptContent.write(to: fileURL)

        let store = TodoStore(fileURL: fileURL)

        #expect(store.items.isEmpty)
        #expect(store.archive.isEmpty)
        #expect(store.isSaveAllowed)
        // 原文件应被改名备份，损坏内容原样保留
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        let backupURL = try #require(try backupFileURL())
        #expect(try Data(contentsOf: backupURL) == corruptContent)

        // 备份完成后可以正常开始新数据的读写
        store.add("新待办")
        let reloaded = TodoStore(fileURL: fileURL)
        #expect(reloaded.items.map(\.text) == ["新待办"])
        #expect(try Data(contentsOf: backupURL) == corruptContent)
    }

    @Test func legacyFileWithoutVersionStillLoads() throws {
        let legacyJSON = """
        {
          "items": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "text": "旧格式待办",
              "createdAt": "2026-08-17T04:00:00Z"
            }
          ],
          "archive": []
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let store = TodoStore(fileURL: fileURL)

        #expect(store.items.map(\.text) == ["旧格式待办"])
        #expect(store.isSaveAllowed)
        #expect(try backupFileURL() == nil)
    }

    @Test func saveWritesCurrentVersionField() throws {
        let store = TodoStore(fileURL: fileURL)
        store.add("带版本号保存")

        let data = try Data(contentsOf: fileURL)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["version"] as? Int == 2)
    }

    @Test func firstSaveOfDayBacksUpExistingDataBeforeOverwrite() throws {
        let originalJSON = """
        {
          "version": 1,
          "items": [],
          "archive": []
        }
        """
        try Data(originalJSON.utf8).write(to: fileURL)
        let store = TodoStore(fileURL: fileURL)

        store.add("触发每日备份")

        let backupURL = try #require(try dailyBackupFileURLs().first)
        #expect(try Data(contentsOf: backupURL) == Data(originalJSON.utf8))
    }

    @Test func dailyBackupsKeepOnlyLatestSevenFiles() throws {
        try Data("{\"version\":1,\"items\":[],\"archive\":[]}".utf8).write(to: fileURL)
        let backupDirectory = directoryURL.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        for day in 1...8 {
            let suffix = String(format: "202608%02d", day)
            let url = backupDirectory.appendingPathComponent("items.json.backup-\(suffix)")
            try Data("backup-\(suffix)".utf8).write(to: url)
        }
        let store = TodoStore(fileURL: fileURL)

        store.add("触发清理旧备份")

        let names = try dailyBackupFileURLs().map(\.lastPathComponent).sorted()
        #expect(names.count == 7)
        #expect(!names.contains("items.json.backup-20260801"))
    }

    private func dailyBackupFileURLs() throws -> [URL] {
        let backupDirectory = directoryURL.appendingPathComponent("Backups", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
    }

    private func backupFileURL() throws -> URL? {
        try FileManager.default
            .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("items.json.corrupt-") }
    }
}
