import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var pomodoro: PomodoroStore
    @ObservedObject var displaySettings: TodoDisplaySettings
    var onClose: () -> Void = { }
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var draft = ""
    @State private var headerHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var showHistory = false
    @State private var selectedArchiveDay: Date?
    @State private var pendingArchiveDeletion: TodoItem?
    @State private var dropPosition: TodoDropPosition?

    private let panelWidth: CGFloat = 260
    private let maxListHeight: CGFloat = 380

    private var viewportHeight: CGFloat {
        if showHistory || displaySettings.limit == nil {
            return min(max(listHeight, 0), maxListHeight)
        }
        let visibleItems = store.items.prefix(displaySettings.limit ?? store.items.count)
        // Use the measured content until every requested row has completed layout.
        guard visibleItems.allSatisfy({ rowHeights[$0.id] != nil }) else {
            return min(max(listHeight, 0), maxListHeight)
        }
        return TodoDisplaySettings.viewportHeight(
            rowHeights: visibleItems.compactMap { rowHeights[$0.id] },
            limit: displaySettings.limit
        )
    }

    private var panelHeight: CGFloat { headerHeight + viewportHeight }

    private var archiveDays: [ArchiveDay] {
        ArchiveHistory.days(from: store.archive)
    }

    private var selectedArchive: (index: Int, day: ArchiveDay)? {
        guard let selectedDay = ArchiveHistory.resolvedSelection(
            selectedArchiveDay,
            in: archiveDays
        ), let index = archiveDays.firstIndex(where: { $0.day == selectedDay }) else {
            return nil
        }
        return (index, archiveDays[index])
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    if showHistory {
                        historyContent
                    } else {
                        listContent
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(HeightReader { height in
                    listHeight = height
                })
            }
            // 模式或日期切换时重建 ScrollView，避免沿用上一页的滚动偏移
            .id(ScrollContentID(
                showHistory: showHistory,
                archiveDay: showHistory ? selectedArchive?.day.day : nil,
                settingsRevision: showHistory ? 0 : displaySettings.revision
            ))
            .frame(height: viewportHeight)
        }
        .frame(width: panelWidth)
        .onPreferenceChange(TodoRowHeightsKey.self) { rowHeights = $0 }
        .onChange(of: panelHeight, initial: true) { _, height in
            guard headerHeight > 0 else { return }
            onHeightChange(height)
        }
        .onReceive(NotificationCenter.default.publisher(for: .floatingTodoToggleHistory)) { _ in
            listHeight = 0
            showHistory.toggle()
        }
        // onChange 备用，保证任意路径触发的切换都能清零高度；每次进入历史页回到最近记录日
        .onChange(of: showHistory) { _, isShowingHistory in
            listHeight = 0
            selectedArchiveDay = isShowingHistory ? archiveDays.first?.day : nil
        }
        // 历史页打开期间新增收档时保留当前日期；当前选择失效时回到最近记录日
        .onChange(of: archiveDays.map(\.day)) { _, _ in
            selectedArchiveDay = ArchiveHistory.resolvedSelection(
                selectedArchiveDay,
                in: archiveDays
            )
        }
        .alert(
            "删除这条记录？",
            isPresented: deleteAlertIsPresented,
            presenting: pendingArchiveDeletion
        ) { item in
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                removeArchivedItem(item) {
                    store.deleteArchived(item)
                }
            }
        } message: { item in
            Text("“\(item.text)”将被永久删除，此操作无法撤销。")
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var deleteAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingArchiveDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingArchiveDeletion = nil
                }
            }
        )
    }

    @ViewBuilder private var header: some View {
        VStack(spacing: 0) {
            if showHistory {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(.secondary)
                    Text("收档历史")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        listHeight = 0
                        showHistory = false
                    } label: {
                        Image(systemName: "chevron.backward.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回待办")
                    .help("返回待办")
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("隐藏窗口")
                    .help("隐藏窗口")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                if !archiveDays.isEmpty {
                    Divider()
                    archiveDayPicker
                }
            } else {
                HStack(spacing: 6) {
                    TextField("正在干什么…", text: $draft)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            store.add(draft)
                            draft = ""
                        }
                    Button {
                        listHeight = 0
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("查看收档历史")
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("隐藏窗口")
                    .help("隐藏窗口")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            Divider()
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(HeightReader { height in
            headerHeight = height
        })
    }

    @ViewBuilder private var archiveDayPicker: some View {
        if let selectedArchive {
            let label = ArchiveHistory.label(for: selectedArchive.day.day)

            HStack {
                Button {
                    selectArchiveDay(at: selectedArchive.index + 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(selectedArchive.index == archiveDays.count - 1)
                .accessibilityLabel("查看更早的收档记录")
                .help("查看更早的收档记录")

                Spacer()

                Text(label)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .accessibilityLabel("当前日期，\(label)")

                Spacer()

                Button {
                    selectArchiveDay(at: selectedArchive.index - 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(selectedArchive.index == 0)
                .accessibilityLabel("查看更新的收档记录")
                .help("查看更新的收档记录")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
    }

    @ViewBuilder private var listContent: some View {
        VStack(spacing: 0) {
            ForEach(store.items) { item in
                TodoRow(
                    item: item,
                    pomodoro: pomodoro,
                    onToggle: { store.toggle(item) },
                    onToggleFocus: { store.toggleFocus(item) },
                    onArchive: { store.archiveItem(item) },
                    onDelete: { store.delete(item) },
                    onEdit: { store.updateText($0, for: item.id) },
                    onDropPosition: { after in
                        dropPosition = after.map { TodoDropPosition(itemID: item.id, after: $0) }
                    },
                    onDrop: { source, after in
                        store.move(itemID: source, relativeTo: item.id, after: after)
                    },
                    onDragEnd: {
                        dropPosition = nil
                    }
                )
                .overlay(alignment: dropPosition?.after == true ? .bottom : .top) {
                    if dropPosition?.itemID == item.id {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .padding(.horizontal, 12)
                            .allowsHitTesting(false)
                    }
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(
                        key: TodoRowHeightsKey.self,
                        value: [item.id: geometry.size.height]
                    )
                })
            }
        }
        // 空列表时不留内边距，列表区高度归零
        .padding(.vertical, store.items.isEmpty ? 0 : 6)
    }

    /// 收档历史：只读展示，只在有记录的日期之间切换
    @ViewBuilder private var historyContent: some View {
        if archiveDays.isEmpty {
            Text("还没有收档记录")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else if let selectedArchive {
            let selectedItems = selectedArchive.day.items
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(selectedItems) { item in
                        ArchiveRow(
                            item: item,
                            onRestore: {
                                removeArchivedItem(item) {
                                    store.restoreArchived(item)
                                }
                            },
                            onDelete: { pendingArchiveDeletion = item }
                        )
                    }
                }
                .padding(.top, 6)

                Text("共 \(selectedItems.count) 项")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 5)
                    .padding(.bottom, 8)
            }
        }
    }

    private func selectArchiveDay(at index: Int) {
        guard archiveDays.indices.contains(index) else { return }
        selectedArchiveDay = archiveDays[index].day
    }

    private func removeArchivedItem(_ item: TodoItem, action: () -> Void) {
        guard let selectedArchive else {
            action()
            return
        }
        let removesSelectedDay = selectedArchive.day.items.count == 1
            && selectedArchive.day.items[0].id == item.id
        let adjacentDay = removesSelectedDay
            ? ArchiveHistory.adjacentDay(
                afterRemovingDayAt: selectedArchive.index,
                from: archiveDays
            )
            : selectedArchiveDay
        action()
        selectedArchiveDay = adjacentDay
    }
}

private struct ScrollContentID: Hashable {
    let showHistory: Bool
    let archiveDay: Date?
    let settingsRevision: Int
}

private struct TodoRowHeightsKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension Notification.Name {
    static let floatingTodoToggleHistory = Notification.Name("FloatingTodoToggleHistory")
}

private struct ArchiveRow: View {
    let item: TodoItem
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false


    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.text)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 4)

            if item.archivedFocus == true {
                Image(systemName: "star.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.76, green: 0.56, blue: 0.18))
                    .accessibilityLabel("收档时的重点任务")
                    .help("收档时的重点任务")
            }

            HStack(spacing: 6) {
                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 18, height: 18)
                        .foregroundStyle(hovering ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("恢复为未完成待办")
                .help("恢复为未完成待办")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 18, height: 18)
                        .foregroundStyle(hovering ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除这条收档记录")
                .help("删除这条收档记录")
            }
            .font(.system(size: 13))
            .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(hovering ? Color.white.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    @ObservedObject var pomodoro: PomodoroStore
    let onToggle: () -> Void
    let onToggleFocus: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onEdit: (String) -> Void
    let onDropPosition: (Bool?) -> Void
    let onDrop: (UUID, Bool) -> Void
    let onDragEnd: () -> Void

    @State private var hovering = false
    @State private var editing = false
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    private var isDone: Bool { item.completedAt != nil }

    private var isFocusing: Bool { pomodoro.taskID == item.id }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    HStack(spacing: 0) {
                        if editing {
                            TextField("待办内容", text: $editText)
                                .textFieldStyle(.plain)
                                .focused($editFocused)
                                .onSubmit { finishEditing(save: true) }
                                .onExitCommand { finishEditing(save: false) }
                                .onChange(of: editFocused) { _, focused in
                                    if !focused && editing { finishEditing(save: true) }
                                }
                        } else {
                            Text(item.text)
                                .strikethrough(isDone)
                                .foregroundStyle(isDone ? Color.secondary : Color.primary)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                    }
                    .overlay {
                        if !editing {
                            TodoDragSource(item: item, onEdit: {
                                editText = item.text
                                editing = true
                                editFocused = true
                            }, onPosition: onDropPosition, onDrop: onDrop, onEnd: onDragEnd)
                        }
                    }

                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let focused = item.isFocused(on: context.date)
                        Button(action: onToggleFocus) {
                            Image(systemName: focused ? "star.fill" : "star")
                                .font(.system(size: 13))
                                .foregroundStyle(focused
                                    ? Color(red: 0.76, green: 0.56, blue: 0.18)
                                    : Color.secondary)
                                .opacity(isDone ? 0.65 : 1)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .opacity(focused || hovering ? 1 : 0)
                        .help(focused ? "取消今日重点" : "标为今日重点（仅当天有效）")
                        .accessibilityLabel(focused ? "取消今日重点" : "标为今日重点")
                    }

                    if !isDone && (hovering || isFocusing) {
                        Button { pomodoro.start(taskID: item.id) } label: {
                            Image(systemName: "timer")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(pomodoro.phase != .idle)
                        .help(isFocusing ? "当前专注任务" : pomodoro.startHelp)
                        .accessibilityLabel(isFocusing ? "当前专注任务" : "开始专注")
                    }
                    if hovering {
                        if isDone {
                            Button(action: onArchive) {
                                Image(systemName: "archivebox")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("收档这条")
                        }
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("删除这条")
                    }
                }

                if isFocusing {
                    HStack(spacing: 12) {
                        Text(pomodoro.timeText)
                            .monospacedDigit()
                            .accessibilityLabel("剩余时间 \(pomodoro.timeText)")
                        if pomodoro.phase == .finished {
                            Button("再来一轮") { pomodoro.restart() }
                            Button("收起") { pomodoro.dismiss() }
                        } else {
                            Button(pomodoro.phase == .paused ? "继续" : "暂停") {
                                if pomodoro.phase == .paused { pomodoro.resume() }
                                else { pomodoro.pause() }
                            }
                            Button("结束") { pomodoro.end() }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background {
            TodoDropTarget(item: item, onPosition: onDropPosition, onDrop: onDrop)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private func finishEditing(save: Bool) {
        guard editing else { return }
        editing = false
        if save { onEdit(editText) }
        editFocused = false
    }
}

private struct HeightReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.size.height) }
                .onChange(of: geo.size.height) { _, height in onChange(height) }
        }
    }
}
