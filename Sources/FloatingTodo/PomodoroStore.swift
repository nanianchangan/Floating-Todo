import Foundation
import Combine

/// A single, memory-only focus session, independent of row/window lifetime.
final class PomodoroStore: ObservableObject {
    enum Phase { case idle, running, paused, finished }

    static let duration: TimeInterval = 25 * 60
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var taskID: UUID?
    @Published private(set) var remainingSeconds = 0

    private let now: () -> TimeInterval
    private let automaticallyTicks: Bool
    private var deadline: TimeInterval?
    private var remaining: TimeInterval = 0
    private var timer: Timer?
    private var itemsSubscription: AnyCancellable?
    private weak var todoStore: TodoStore?

    init(todoStore: TodoStore,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticallyTicks: Bool = true) {
        self.todoStore = todoStore
        self.now = now
        self.automaticallyTicks = automaticallyTicks
        itemsSubscription = todoStore.$items.sink { [weak self] items in
            guard let self, let taskID = self.taskID else { return }
            if !items.contains(where: { $0.id == taskID && $0.completedAt == nil }) {
                self.end()
            }
        }
    }

    deinit { timer?.invalidate() }

    var timeText: String {
        String(format: "%02d:xx", remainingSeconds / 60)
    }

    var startHelp: String {
        switch phase {
        case .idle: return "开始专注"
        case .running, .paused: return "请先结束当前专注"
        case .finished: return "请先收起当前专注"
        }
    }

    func start(taskID: UUID) {
        guard phase == .idle,
              todoStore?.items.contains(where: { $0.id == taskID && $0.completedAt == nil }) == true else { return }
        self.taskID = taskID
        remaining = Self.duration
        remainingSeconds = Int(Self.duration)
        run()
    }

    func pause() {
        guard phase == .running else { return }
        refresh()
        guard phase == .running else { return }
        phase = .paused
        deadline = nil
        stopTimer()
    }

    func resume() {
        guard phase == .paused else { return }
        run()
    }

    func end() {
        stopTimer()
        deadline = nil
        remaining = 0
        remainingSeconds = 0
        taskID = nil
        phase = .idle
    }

    func restart() {
        guard phase == .finished, let taskID else { return }
        end()
        start(taskID: taskID)
    }

    func dismiss() {
        guard phase == .finished else { return }
        end()
    }

    func prepareForSleep() { pause() }

    /// Read elapsed monotonic time; delayed callbacks never accumulate clock drift.
    func refresh() {
        guard phase == .running, let deadline else { return }
        remaining = max(0, deadline - now())
        let seconds = Int(ceil(remaining))
        if remainingSeconds != seconds { remainingSeconds = seconds }
        if remaining == 0 {
            self.deadline = nil
            phase = .finished
            stopTimer()
        }
    }

    private func run() {
        deadline = now() + remaining
        phase = .running
        guard automaticallyTicks else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
