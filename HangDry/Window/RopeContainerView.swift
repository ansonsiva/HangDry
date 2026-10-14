import AppKit

/// 面板的内容视图，负责三件事：
/// 1. 承载 SwiftUI 画的绳子和衣服（hosting view 固定高度、贴顶摆放，窗口伸缩时不用重新布局）；
/// 2. 拖文件到屏幕顶部时铺一块不透明的“晾衣台”，连菜单栏一起盖住。
///    不用毛玻璃：实时模糊这么大一块区域（5K 屏上 5120×380 像素），拖拽时每帧都要重算，会把 WindowServer 占满，整台电脑卡住。
///    整块区域都不透明，拖拽只会交给这个窗口，下面的 App 不会和它抢；
/// 3. 用 AppKit 接收拖放，进入、离开只在越过晾衣台边界时发生。
final class RopeContainerView: NSView {
    weak var model: AppModel?

    /// 盖住菜单栏的高度；晾衣台出现时等于菜单栏高度，平时为 0。
    var topInset: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    private let host: NSView
    private let shelf = ShelfBackgroundView()

    init(host: NSView) {
        self.host = host
        super.init(frame: .zero)

        shelf.alphaValue = 0
        shelf.isHidden = true

        addSubview(shelf)
        addSubview(host)
        registerForDraggedTypes(DropLoader.draggedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // hosting view 的顶边始终贴着菜单栏下沿；窗口收起时只露出最上面一条绳子
        host.frame = NSRect(x: 0, y: bounds.height - topInset - RopeMetrics.expandedHeight,
                            width: bounds.width, height: RopeMetrics.expandedHeight)
        shelf.frame = bounds
    }

    var isShelfVisible: Bool { !shelf.isHidden }

    func setShelfVisible(_ visible: Bool) {
        guard visible != isShelfVisible || shelf.alphaValue != (visible ? 1 : 0) else { return }
        if visible { shelf.isHidden = false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.15 : 0.2
            shelf.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !visible, self.shelf.alphaValue == 0 else { return }
                self.shelf.isHidden = true
            }
        }
    }

    // MARK: - 拖放

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(with: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(with: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model?.dropExited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let model else { return false }
        // 拖的是绳上自己的衣服：调整位置
        if model.isDraggingOut {
            model.performReorder()
            return true
        }
        // 拖拽剪贴板只在这一刻有效，必须同步读出来
        let payload = DropLoader.read(sender.draggingPasteboard)
        model.performDrop(payload)
        return payload != nil
    }

    private func update(with sender: NSDraggingInfo) -> NSDragOperation {
        guard let model else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        if model.isDraggingOut {
            model.dropUpdated(atX: point.x, width: bounds.width, count: model.draggedIDs.count)
            return .move
        }
        let count = sender.draggingPasteboard.pasteboardItems?.count ?? 1
        model.dropUpdated(atX: point.x, width: bounds.width, count: max(count, 1))
        return .copy
    }
}

/// 晾衣台的底：半透明纯色加一层很淡的强调色，底边圆角，跟随浅色、深色模式。
private final class ShelfBackgroundView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer?.borderWidth = 0.5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = isDark ? NSColor(white: 0.13, alpha: 0.92) : NSColor(white: 0.97, alpha: 0.92)
        let tinted = base.blended(withFraction: 0.08, of: .controlAccentColor) ?? base
        layer?.backgroundColor = tinted.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}
