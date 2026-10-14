import AppKit
import SwiftUI

/// 卡片上的鼠标交互用 AppKit 实现：点选、双击打开、右键菜单，以及把文件拖出去（支持多选一起拖）。
/// 拖到别处默认复制，按住 ⌘ 拖是移动。
struct ClothesInteraction: NSViewRepresentable {
    let id: UUID
    let path: String
    let model: AppModel
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> ClothesInteractionView {
        let view = ClothesInteractionView()
        configure(view)
        return view
    }

    func updateNSView(_ view: ClothesInteractionView, context: Context) {
        configure(view)
    }

    private func configure(_ view: ClothesInteractionView) {
        view.itemID = id
        view.model = model
        view.onHover = onHover
        if view.toolTip != path { view.toolTip = path }
    }
}

final class ClothesInteractionView: NSView, NSDraggingSource {
    var itemID: UUID?
    weak var model: AppModel?
    var onHover: ((Bool) -> Void)?

    private var mouseDownEvent: NSEvent?
    /// 在已选中的多项上按下鼠标：如果没有拖动，松开时才改成单选。
    private var selectsOnlyThisOnMouseUp = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        guard let itemID, let model else { return }
        if event.clickCount == 2 {
            mouseDownEvent = nil
            model.open([itemID])
            return
        }
        mouseDownEvent = event
        let isExtending = !event.modifierFlags.intersection([.command, .shift]).isEmpty
        selectsOnlyThisOnMouseUp = !isExtending && model.selection.contains(itemID)
        if !selectsOnlyThisOnMouseUp {
            model.select(itemID, extending: isExtending)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if selectsOnlyThisOnMouseUp, let itemID {
            model?.select(itemID, extending: false)
        }
        selectsOnlyThisOnMouseUp = false
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent, let itemID, let model else { return }
        let start = down.locationInWindow
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        mouseDownEvent = nil
        selectsOnlyThisOnMouseUp = false

        let dragged = model.dragItems(from: itemID)
        guard !dragged.isEmpty else { return }
        let ids = model.targets(for: itemID)

        let origin = convert(start, from: nil)
        let size = NSSize(width: 56, height: 56)
        let draggingItems = dragged.enumerated().map { index, entry in
            let url = entry.url
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(index) * 4
            let frame = NSRect(x: origin.x - size.width / 2 + offset, y: origin.y - size.height / 2 - offset,
                               width: size.width, height: size.height)
            item.setDraggingFrame(frame, contents: ThumbnailCache.shared.dragImage(for: url, item: entry.id))
            return item
        }
        model.beginDraggingClothes(ids)
        let session = beginDraggingSession(with: draggingItems, event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let itemID, let model else { return nil }
        return model.contextMenu(for: itemID)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // 在自己的晾衣台上是调整位置；拖到别的 App 默认复制，按住 ⌘ 是移动
        guard context == .outsideApplication else { return .move }
        return NSEvent.modifierFlags.contains(.command) ? .move : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model?.endDraggingClothes()
        if operation.contains(.move) {
            model?.store.refreshMovedItems()
        }
    }
}
