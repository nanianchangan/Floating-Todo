import AppKit
import SwiftUI

/// 允许 nonactivating panel 成为 key window，输入框才能接收键盘
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // lazy：单实例检测通过之前不触碰数据文件
    private lazy var store = TodoStore()
    private lazy var displaySettings = TodoDisplaySettings()
    private var panel: FloatingPanel?
    private var statusItem: NSStatusItem?
    // 保存 block 版 addObserver 返回的 token，否则观察者无法移除
    private var rearchiveObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 已有实例在运行时立刻退出，避免两个进程互相覆盖数据文件
        if activateExistingInstance() {
            NSApp.terminate(nil)
            return
        }
        // swift run 时没有 Info.plist（LSUIElement），代码里兜底隐藏 Dock 图标
        NSApp.setActivationPolicy(.accessory)
        setUpPanel()
        setUpStatusItem()
        // 跨零点、手动改系统时间、切换时区都重新检查一次跨天归档
        let rearchiveTriggers: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
        ]
        for name in rearchiveTriggers {
            rearchiveObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.store.archiveOldCompleted()
            })
        }
        showPanel()
    }

    deinit {
        rearchiveObservers.forEach(NotificationCenter.default.removeObserver(_:))
    }

    /// 找到同 bundle ID 的其他实例则激活它；swift run 无 bundle ID，跳过检测
    private func activateExistingInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let existing = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing else { return false }
        existing.activate()
        return true
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        ensureStatusItemVisible()
        showPanel()
        return true
    }

    private func setUpPanel() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 200),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .utilityWindow

        // 半透明材质背景，SwiftUI 内容铺在上面
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        let rootView = ContentView(
            store: store,
            displaySettings: displaySettings,
            onClose: { [weak self] in self?.panel?.orderOut(nil) },
            onHeightChange: { [weak self] height in self?.setPanelContentHeight(height) }
        )
        let hosting = NSHostingView(rootView: rootView)
        // 关掉 NSHostingView 自动插入的安全区内边距，避免标题栏安全区在顶部留出空白
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])
        panel.contentView = effect

        // 记住窗口位置。注意 setFrameAutosaveName 本身会再次应用已保存的 frame，
        // 所以越界校验必须放在它之后，否则修正结果会被盖回去
        _ = panel.setFrameUsingName("FloatingTodoPanel")
        panel.setFrameAutosaveName("FloatingTodoPanel")
        // 首次运行或记录的位置已不在任何屏幕上（如外接屏拔掉）时，放到主屏右上角附近
        if !frameIsUsablyVisible(panel.frame), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 24,
                y: visible.maxY - panel.frame.height - 24
            ))
        }

        self.panel = panel
    }

    /// 窗口与某个屏幕可见区域的重叠部分足够大，才算用户够得着
    private func frameIsUsablyVisible(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let overlap = frame.intersection(screen.visibleFrame)
            return overlap.width >= 40 && overlap.height >= 20
        }
    }

    /// 内容高度变化时调整窗口高度，保持顶边不动
    private func setPanelContentHeight(_ height: CGFloat) {
        guard let panel, height > 0 else { return }
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private func setUpStatusItem() {
        guard statusItem == nil else {
            ensureStatusItemVisible()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "FloatingTodoStatusItem"
        // 不允许用户把唯一的恢复入口从菜单栏中拖走。
        item.behavior = []

        if let button = item.button {
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            if let image = NSImage(
                systemSymbolName: "checklist",
                accessibilityDescription: "FloatingTodo 清单"
            )?.withSymbolConfiguration(configuration) {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyDown
                button.title = ""
            } else {
                // SF Symbol 不可用时仍保留一个醒目的菜单栏入口。
                button.image = nil
                button.title = "✓"
            }
            button.toolTip = "FloatingTodo 清单"
            button.setAccessibilityLabel("FloatingTodo 清单")
        }

        let menu = NSMenu()
        let toggle = NSMenuItem(title: "显示/隐藏窗口", action: #selector(toggleWindow), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let archiveNow = NSMenuItem(title: "收档已完成条目", action: #selector(archiveCompletedNow), keyEquivalent: "")
        archiveNow.target = self
        menu.addItem(archiveNow)
        let history = NSMenuItem(title: "查看收档历史", action: #selector(toggleHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)
        let visibleItems = NSMenuItem(title: "待办显示条数…", action: #selector(editVisibleItemLimit), keyEquivalent: "")
        visibleItems.target = self
        menu.addItem(visibleItems)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 FloatingTodo", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        item.isVisible = true
    }

    private func ensureStatusItemVisible() {
        guard let statusItem else {
            setUpStatusItem()
            return
        }
        statusItem.isVisible = true
    }

    private func showPanel() {
        // 通知漏触发的兜底：每次显示面板时顺手检查一次跨天归档
        store.archiveOldCompleted()
        panel?.orderFrontRegardless()
    }

    @objc private func toggleWindow() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    @objc private func archiveCompletedNow() {
        store.archiveCompleted()
    }

    @objc private func toggleHistory() {
        showPanel()
        NotificationCenter.default.post(name: .floatingTodoToggleHistory, object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func editVisibleItemLimit() {
        let alert = NSAlert()
        alert.messageText = "待办显示条数"
        let hint = "最多显示几条待办；留空显示全部。窗口仍保留当前高度上限，超出可滚动查看。"
        alert.informativeText = hint
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "全部"
        input.stringValue = displaySettings.limit.map(String.init) ?? ""
        input.setAccessibilityLabel("最多显示的待办条数，留空显示全部")
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            if displaySettings.save(input.stringValue) { return }
            alert.informativeText = "请输入正整数，或留空显示全部。\n\n" + hint
            alert.window.makeFirstResponder(input)
        }
    }
}
