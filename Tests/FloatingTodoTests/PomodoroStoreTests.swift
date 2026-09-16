import Foundation
import Testing
@testable import FloatingTodo

struct PomodoroStoreTests {
    private func withStore(_ body: (TodoStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TodoStore(fileURL: directory.appendingPathComponent("items.json"))
        store.add("第一项")
        store.add("第二项")
        try body(store)
    }

    @Test func delayedTicksPauseResumeAndFinish() throws {
        try withStore { todos in
            var time: TimeInterval = 100
            let timer = PomodoroStore(todoStore: todos, now: { time }, automaticallyTicks: false)
            timer.start(taskID: todos.items[0].id)
            #expect(timer.timeText == "25:00")
            time += 61.25
            timer.refresh()
            #expect(timer.timeText == "23:59")
            timer.pause()
            time += 500
            timer.refresh()
            #expect(timer.phase == .paused)
            #expect(timer.timeText == "23:59")
            timer.resume()
            time += 1438.5
            timer.refresh()
            #expect(timer.timeText == "00:01")
            time += 10
            timer.refresh()
            #expect(timer.phase == .finished)
            #expect(timer.timeText == "00:00")
            let id = timer.taskID
            timer.refresh()
            timer.pause()
            timer.resume()
            #expect(timer.phase == .finished)
            #expect(timer.taskID == id)
            #expect(todos.items[0].completedAt == nil)
            timer.restart()
            #expect(timer.phase == .running)
            #expect(timer.taskID == id)
            #expect(timer.timeText == "25:00")
            time += 1500
            timer.refresh()
            timer.dismiss()
            #expect(timer.phase == .idle)
            #expect(timer.taskID == nil)
        }
    }

    @Test func exclusiveSessionAndTaskMutations() throws {
        try withStore { todos in
            let timer = PomodoroStore(todoStore: todos, automaticallyTicks: false)
            let first = todos.items[0]
            let other = todos.items[1]
            timer.start(taskID: first.id)
            timer.start(taskID: other.id)
            #expect(timer.taskID == first.id)
            todos.move(itemID: first.id, relativeTo: other.id, after: true)
            #expect(timer.taskID == first.id)
            todos.toggle(other)
            #expect(timer.phase == .running)
            timer.pause()
            timer.start(taskID: other.id)
            #expect(timer.taskID == first.id)
            todos.toggle(first)
            #expect(timer.phase == .idle)
            #expect(timer.taskID == nil)
            timer.start(taskID: first.id)
            #expect(timer.phase == .idle)
            todos.toggle(first)
            timer.start(taskID: first.id)
            todos.delete(first)
            #expect(timer.phase == .idle)
            timer.start(taskID: UUID())
            #expect(timer.phase == .idle)
        }
    }

    @Test func sleepEndsAndFreshLaunch() throws {
        try withStore { todos in
            var time: TimeInterval = 0
            let timer = PomodoroStore(todoStore: todos, now: { time }, automaticallyTicks: false)
            timer.start(taskID: todos.items[0].id)
            time = 60
            timer.prepareForSleep()
            time = 3600
            timer.refresh()
            #expect(timer.phase == .paused)
            #expect(timer.timeText == "24:00")
            timer.resume()
            time += 30
            timer.refresh()
            #expect(timer.timeText == "23:30")
            timer.end()
            #expect(timer.phase == .idle)
            #expect(timer.taskID == nil)
            timer.start(taskID: todos.items[1].id)
            #expect(timer.timeText == "25:00")
            let fresh = PomodoroStore(todoStore: todos, automaticallyTicks: false)
            #expect(fresh.phase == .idle)
            #expect(fresh.taskID == nil)
        }
    }

    @Test func deadlineAtSleepAndFinishedSessionCannotSwitch() throws {
        try withStore { todos in
            var time: TimeInterval = 0
            let timer = PomodoroStore(todoStore: todos, now: { time }, automaticallyTicks: false)
            let first = todos.items[0]
            timer.start(taskID: first.id)
            time = 1500
            timer.prepareForSleep()
            #expect(timer.phase == .finished)
            timer.start(taskID: todos.items[1].id)
            #expect(timer.taskID == first.id)
            #expect(timer.timeText == "00:00")
            todos.delete(first)
            #expect(timer.phase == .idle)
        }
    }
}
