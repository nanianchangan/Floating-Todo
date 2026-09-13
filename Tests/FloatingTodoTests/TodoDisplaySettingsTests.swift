import Foundation
import Testing
@testable import FloatingTodo

struct TodoDisplaySettingsTests {
    @Test func validatesAndPersistsWithoutReplacingValueOnInvalidInput() throws {
        let suite = "TodoDisplaySettingsTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TodoDisplaySettings(defaults: defaults)
        #expect(settings.limit == nil)
        #expect(settings.save(" 5 \n"))
        #expect(TodoDisplaySettings(defaults: defaults).limit == 5)
        for invalid in ["0", "-1", "1.5", "abc", "+2", "1 2", String(repeating: "9", count: 50)] {
            #expect(!settings.save(invalid))
            #expect(settings.limit == 5)
            #expect(TodoDisplaySettings(defaults: defaults).limit == 5)
        }
        #expect(settings.save(" \n\t"))
        #expect(TodoDisplaySettings(defaults: defaults).limit == nil)
    }

    @Test func heightCountsWholeItemsAndKeepsExistingCeiling() {
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [], limit: 3) == 0)
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [25, 55, 40], limit: 2) == 92)
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [25, 55], limit: 5) == 92)
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [25, 55], limit: 2) == 92)
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [25, 55, 40], limit: nil) == 132)
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [200, 200], limit: 2) == 380)
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [200, 200], limit: nil) == 380)
        // A hover-induced wrap or a removed/restored row changes the measured prefix.
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [55, 55, 40], limit: 2) == 122)
        #expect(TodoDisplaySettings.viewportHeight(rowHeights: [40], limit: 2) == 52)
    }
}
