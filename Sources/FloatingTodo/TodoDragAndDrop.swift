import AppKit
import SwiftUI
import UniformTypeIdentifiers

let todoDragType = UTType(exportedAs: "local.tools.floatingtodo.item", conformingTo: .data)

struct TodoDropPosition: Equatable {
    let itemID: UUID
    let after: Bool
}

/// 原生拖动来源只覆盖文字和空白区，按钮仍由 SwiftUI 处理。
/// 显式禁止背景移动，避免 NSPanel 把行拖动当作窗口拖动。
struct TodoDragSource: NSViewRepresentable {
    let item: TodoItem
    let onPosition: (Bool?) -> Void
    let onDrop: (UUID, Bool) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> TodoDragView {
        let view = TodoDragView()
        view.registerForDraggedTypes([NSPasteboard.PasteboardType(todoDragType.identifier)])
        return view
    }

    func updateNSView(_ view: TodoDragView, context: Context) {
        view.item = item
        view.onPosition = onPosition
        view.onDrop = onDrop
        view.onEnd = onEnd
    }
}

final class TodoDragView: NSView, NSDraggingSource {
    var item: TodoItem?
    var onPosition: (Bool?) -> Void = { _ in }
    var onDrop: (UUID, Bool) -> Void = { _, _ in }
    var onEnd: () -> Void = {}
    private var pressPoint: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressPoint = event.locationInWindow
    }

    override func mouseUp(with event: NSEvent) { pressPoint = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressPoint, let item,
              hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 4
        else { return }
        pressPoint = nil
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.id.uuidString, forType: NSPasteboard.PasteboardType(todoDragType.identifier))
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let previewSize = bounds.size
        let preview = NSImage(size: previewSize, flipped: false) { rect in
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            (item.text as NSString).draw(in: rect, withAttributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style
            ])
            return true
        }
        draggingItem.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func sourceID(_ sender: NSDraggingInfo) -> UUID? {
        guard let source = sender.draggingSource as? TodoDragView,
              source.window === window,
              let value = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(todoDragType.identifier)),
              let id = UUID(uuidString: value), source.item?.id == id else { return nil }
        return id
    }

    private func isAfter(_ sender: NSDraggingInfo) -> Bool {
        // NSView 的 y 轴向上；下半区对应插在目标后面。
        convert(sender.draggingLocation, from: nil).y < bounds.midY
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let id = sourceID(sender) else { return [] }
        onPosition(id == item?.id ? nil : isAfter(sender))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onPosition(nil) }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        sourceID(sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let id = sourceID(sender) else { return false }
        onDrop(id, isAfter(sender))
        onPosition(nil)
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        pressPoint = nil
        onEnd()
    }
}
