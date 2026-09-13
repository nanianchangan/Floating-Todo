import SwiftUI

struct ContentView: View {
    @ObservedObject var store: TodoStore
    var onClose: () -> Void = { }
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var draft = ""
    @State private var headerHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0
    @State private var showHistory = false
    @State private var selectedArchiveDay: Date?
    @State private var pendingArchiveDeletion: TodoItem?

    private let panelWidth: CGFloat = 260
    private let maxListHeight: CGFloat = 380

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
                    reportPanelHeight(headerHeight: headerHeight, listHeight: height)
                })
            }
            // 模式或日期切换时重建 ScrollView，避免沿用上一页的滚动偏移
            .id(ScrollContentID(
                showHistory: showHistory,
                archiveDay: showHistory ? selectedArchive?.day.day : nil
            ))
            .frame(height: min(max(listHeight, 0), maxListHeight))
        }
        .frame(width: panelWidth)
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
            reportPanelHeight(headerHeight: height, listHeight: listHeight)
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

    private func reportPanelHeight(headerHeight: CGFloat, listHeight: CGFloat) {
        guard headerHeight > 0 else { return }
        onHeightChange(headerHeight + min(max(listHeight, 0), maxListHeight))
    }

    @ViewBuilder private var listContent: some View {
        VStack(spacing: 0) {
            ForEach(store.items) { item in
                TodoRow(
                    item: item,
                    onToggle: { store.toggle(item) },
                    onArchive: { store.archiveItem(item) },
                    onDelete: { store.delete(item) }
                )
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
    let onToggle: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var isDone: Bool { item.completedAt != nil }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(item.text)
                .strikethrough(isDone)
                .foregroundStyle(isDone ? Color.secondary : Color.primary)
                .lineLimit(3)

            Spacer(minLength: 0)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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
