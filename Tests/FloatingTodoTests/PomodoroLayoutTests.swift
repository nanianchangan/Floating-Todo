import AppKit
import SwiftUI
import Testing
@testable import FloatingTodo

struct PomodoroLayoutTests {
    @Test @MainActor func expandedRowsFitPanelAndProducePreview() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let todos = TodoStore(fileURL: directory.appendingPathComponent("items.json"))
        todos.add("一天投一个企业")
        todos.add("加一个番茄钟")
        todos.add("国庆旅行攻略")
        var time: TimeInterval = 0
        let timer = PomodoroStore(todoStore: todos, now: { time }, automaticallyTicks: false)
        let suite = "PomodoroLayoutTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TodoDisplaySettings(defaults: defaults)
        var measuredHeight: CGFloat = 0
        let root = ContentView(store: todos, pomodoro: timer, displaySettings: settings,
                               onHeightChange: { measuredHeight = $0 })
        let host = NSHostingView(rootView: root.background(Color(nsColor: .windowBackgroundColor)))
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 250),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        if ProcessInfo.processInfo.environment["POMODORO_PREVIEW_DIR"] != nil {
            window.orderFront(nil)
        }
        func settle() {
            for _ in 0..<5 {
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
        }
        func preview(_ name: String) throws {
            guard ProcessInfo.processInfo.environment["POMODORO_PREVIEW_DIR"] != nil else { return }
            let output = ProcessInfo.processInfo.environment["POMODORO_PREVIEW_DIR"]!
            window.setContentSize(NSSize(width: 260, height: measuredHeight))
            settle()
            let rect = host.bounds
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: rect))
            host.cacheDisplay(in: rect, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
        }
        settle()
        let base = measuredHeight
        #expect(base > 0)
        timer.start(taskID: todos.items[1].id)
        time = 378
        timer.refresh()
        settle()
        let expanded = measuredHeight
        #expect(expanded > base)
        #expect(host.fittingSize.width <= 260)
        try preview("running")
        timer.pause()
        settle()
        #expect(measuredHeight == expanded)
        try preview("paused")
        timer.resume()
        time += 1500
        timer.refresh()
        settle()
        #expect(host.fittingSize.width <= 260)
        #expect(measuredHeight == expanded)
        try preview("finished")
        timer.dismiss()
        settle()
        #expect(measuredHeight == base)
        window.orderOut(nil)
        window.contentView = nil
    }
}
