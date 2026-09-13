import Foundation
import Combine

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date
    var completedAt: Date?

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.completedAt = nil
    }
}

final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var archive: [TodoItem] = []

    private struct FileData: Codable {
        /// 当前存储格式版本；以后字段变更时递增并做迁移
        static let currentVersion = 1

        var version: Int
        var items: [TodoItem]
        var archive: [TodoItem]

        init(items: [TodoItem], archive: [TodoItem]) {
            self.version = Self.currentVersion
            self.items = items
            self.archive = archive
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // 旧文件没有 version 字段，视为版本 1
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            items = try container.decode([TodoItem].self, forKey: .items)
            archive = try container.decode([TodoItem].self, forKey: .archive)
        }
    }

    private let fileURL: URL

    /// 数据文件损坏且备份失败时置 false，禁止 save 覆盖仅存的原始数据
    private(set) var isSaveAllowed = true

    /// 正常运行时的每日备份最多保留最近 7 份，避免备份无限增长
    private let maxDailyBackupCount = 7

    private static func defaultFileURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FloatingTodo", isDirectory: true)
        return dir.appendingPathComponent("items.json")
    }

    init() {
        self.fileURL = Self.defaultFileURL()
        prepareStorageAndLoad()
    }

    /// 测试使用独立文件，避免读写真实用户数据。
    init(fileURL: URL) {
        self.fileURL = fileURL
        prepareStorageAndLoad()
    }

    private func prepareStorageAndLoad() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        load()
        archiveOldCompleted()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(TodoItem(text: trimmed), at: 0)
        save()
    }

    func toggle(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].completedAt = items[i].completedAt == nil ? Date() : nil
        save()
    }

    /// 用户主动删除：物理移除，不进归档
    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// 手动收档单条：把指定的已完成条目立即移入 archive
    func archiveItem(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }),
              items[i].completedAt != nil else { return }
        archive.append(items[i])
        items.remove(at: i)
        save()
    }

    /// 手动收档：把所有已完成条目立即移入 archive，不等第二天
    func archiveCompleted() {
        let done = items.filter { $0.completedAt != nil }
        guard !done.isEmpty else { return }
        archive.append(contentsOf: done)
        items.removeAll { $0.completedAt != nil }
        save()
    }

    /// 恢复收档条目：重置为未完成，并按原创建时间倒序插回待办列表。
    func restoreArchived(_ item: TodoItem) {
        guard let index = archive.firstIndex(where: { $0.id == item.id }) else { return }
        var restored = archive.remove(at: index)
        restored.completedAt = nil
        let insertionIndex = items.firstIndex { $0.createdAt < restored.createdAt }
            ?? items.endIndex
        items.insert(restored, at: insertionIndex)
        save()
    }

    /// 永久删除指定收档条目。
    func deleteArchived(_ item: TodoItem) {
        guard let index = archive.firstIndex(where: { $0.id == item.id }) else { return }
        archive.remove(at: index)
        save()
    }

    /// 把「完成日早于今天」的条目从 items 移入 archive（按自然日判断）
    func archiveOldCompleted() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        var moved = false
        var remaining: [TodoItem] = []
        for item in items {
            if let done = item.completedAt, done < startOfToday {
                archive.append(item)
                moved = true
            } else {
                remaining.append(item)
            }
        }
        if moved {
            items = remaining
            save()
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let file = try? decoder.decode(FileData.self, from: data) {
            items = file.items
            archive = file.archive
        } else {
            backUpCorruptFile()
        }
    }

    /// 数据文件无法读取或解析时改名备份，避免后续 save 覆盖掉用户数据
    private func backUpCorruptFile() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = fileURL
            .appendingPathExtension("corrupt-\(formatter.string(from: Date()))")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
        } catch {
            // 备份失败时原文件还在原位，禁止保存以免覆盖
            isSaveAllowed = false
        }
    }

    /// 每天首次保存前复制一份旧数据，便于误删、误操作或异常写入后恢复
    private func makeDailyBackupIfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let backupDirectory = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        guard (try? FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )) != nil else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let backupURL = backupDirectory
            .appendingPathComponent("\(fileURL.lastPathComponent).backup-\(formatter.string(from: Date()))")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        pruneOldDailyBackups(in: backupDirectory)
    }

    private func pruneOldDailyBackups(in backupDirectory: URL) {
        let prefix = "\(fileURL.lastPathComponent).backup-"
        guard let backups = try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        let dailyBackups = backups
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for backup in dailyBackups.dropFirst(maxDailyBackupCount) {
            try? FileManager.default.removeItem(at: backup)
        }
    }

    private func save() {
        guard isSaveAllowed else { return }
        makeDailyBackupIfNeeded()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(FileData(items: items, archive: archive)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
