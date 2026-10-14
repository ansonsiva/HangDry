import AppKit
import SwiftUI

/// 控制晾衣绳的展开、收起和晾衣台。
/// - 平时只是一条细绳；鼠标在绳上停留时展开，离开后自动收起。
/// - 拖着文件或图片靠近屏幕上方时，绳子垂下一个小标签当目标；
///   拖进菜单栏下方的触发区（或菜单栏），铺开不透明的晾衣台，整块区域都能松手；
///   往下拖离晾衣台就收起，拖拽交还给下面的 App。
@MainActor
final class RopePanelController {
    private let model: AppModel
    private let panel = RopePanel()
    private let container: RopeContainerView
    private var timer: Timer?
    private var hoverSince: Date?
    private var outsideSince: Date?
    private var peekUntil: Date?
    private var dragBaseline: Int
    /// 当前这次拖拽带的是不是文件或图片（按拖拽剪贴板的 changeCount 缓存）
    private var dragCarriesFiles = false
    private var dragTypesChangeCount = -1
    private var isShelfOpen = false
    #if DEBUG
    /// 性能测量用：不拖文件也把晾衣台铺开
    var debugForcesShelf = false
    #endif
    private var isHinting = false
    private var collapseTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private static let hoverDelay: TimeInterval = 0.35
    private static let leaveDelay: TimeInterval = 0.6

    init(model: AppModel) {
        self.model = model
        dragBaseline = NSPasteboard(name: .drag).changeCount

        // hosting view 放在容器里：直接当 contentView 时，SwiftUI 动画会在布局阶段反过来改窗口尺寸，导致 AppKit 抛异常
        let host = FirstMouseHostingView(rootView: RopeView(model: model))
        host.sizingOptions = []
        container = RopeContainerView(host: host)
        container.model = model
        panel.contentView = container
        panel.setFrame(frame(expanded: false), display: false)

        let relayout: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: relayout))
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: relayout))

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// 短暂展开一下（启动时、自动挂上新文件时）。
    func peek(for duration: TimeInterval = 2.5) {
        peekUntil = .now.addingTimeInterval(duration)
        expand()
    }

    /// “一直展开”打开就展开并停住；关掉就立刻收起。
    func pinnedChanged(_ isPinned: Bool) {
        if isPinned {
            expand()
        } else {
            peekUntil = nil
            collapse()
        }
    }

    func expand() {
        collapseTask?.cancel()
        collapseTask = nil
        outsideSince = nil
        guard !model.isExpanded else { return }
        model.store.refreshMovedItems()
        panel.setFrame(frame(expanded: true), display: true)
        withAnimation(.spring(duration: 0.4, bounce: 0.35)) {
            model.isExpanded = true
        }
    }

    func collapse() {
        guard model.isExpanded, !isShelfOpen, collapseTask == nil else { return }
        peekUntil = nil
        withAnimation(.easeIn(duration: 0.18)) {
            model.isExpanded = false
            model.selection = []
        }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            panel.setFrame(frame(expanded: false), display: true)
            collapseTask = nil
        }
    }

    // MARK: - 晾衣台

    private func setShelfOpen(_ open: Bool) {
        guard open != isShelfOpen, let screen else { return }
        isShelfOpen = open
        model.isDragActive = open
        if open {
            container.topInset = screen.frame.maxY - screen.visibleFrame.maxY
            expand()
            panel.setFrame(frame(expanded: true), display: true)
            container.setShelfVisible(true)
        } else {
            container.setShelfVisible(false)
            model.dropExited()
            container.topInset = 0
            if collapseTask == nil {
                panel.setFrame(frame(expanded: model.isExpanded), display: true)
            }
        }
    }

    private func setHinting(_ hinting: Bool) {
        guard hinting != isHinting else { return }
        isHinting = hinting
        if hinting {
            if !model.isExpanded, collapseTask == nil {
                panel.setFrame(frame(expanded: false), display: true)
            }
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { model.isDragHinting = true }
        } else {
            withAnimation(.easeOut(duration: 0.15)) { model.isDragHinting = false }
            if !model.isExpanded, collapseTask == nil {
                panel.setFrame(frame(expanded: false), display: true)
            }
        }
    }

    // MARK: - 布局

    private var screen: NSScreen? { NSScreen.screens.first }

    /// 绳子始终挂在菜单栏下沿；晾衣台打开时窗口向上延伸，把菜单栏也盖住。
    /// 收起时如果正在提示拖拽，窗口留出触发区的高度给小标签。
    private func frame(expanded: Bool) -> NSRect {
        guard let screen else { return .zero }
        let height = if expanded {
            RopeMetrics.expandedHeight
        } else if isHinting {
            RopeMetrics.dragTriggerDepth
        } else {
            RopeMetrics.collapsedHeight
        }
        let bottom = screen.visibleFrame.maxY - height
        let top = isShelfOpen ? screen.frame.maxY : screen.visibleFrame.maxY
        return NSRect(x: screen.frame.minX, y: bottom, width: screen.frame.width, height: top - bottom)
    }

    private func relayout() {
        guard collapseTask == nil, let screen else { return }
        if isShelfOpen { container.topInset = screen.frame.maxY - screen.visibleFrame.maxY }
        panel.setFrame(frame(expanded: model.isExpanded), display: true)
    }

    // MARK: - 鼠标轮询

    /// 用轮询判断鼠标位置和拖拽状态，不需要辅助功能权限，沙盒里也能用。
    private func tick() {
        guard panel.isVisible, NSApp.modalWindow == nil, let screen else { return }

        let mouse = NSEvent.mouseLocation
        let isButtonDown = NSEvent.pressedMouseButtons & 1 != 0
        let dragPasteboard = NSPasteboard(name: .drag)
        if !isButtonDown { dragBaseline = dragPasteboard.changeCount }
        let isDraggingFiles = model.isDragToHangEnabled
            && isButtonDown
            && dragPasteboard.changeCount != dragBaseline
            && carriesFiles(dragPasteboard)
            && !model.isDraggingOut

        let withinScreenX = mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
        // 光标在菜单栏下沿以下多远（进入菜单栏时为负数）
        let depthBelowMenuBar = screen.visibleFrame.maxY - mouse.y
        let inTriggerZone = withinScreenX && depthBelowMenuBar <= RopeMetrics.dragTriggerDepth
        let nearTop = withinScreenX && depthBelowMenuBar <= RopeMetrics.dragHintDistance
        let inPanel = panel.frame.contains(mouse)

        // 拖进触发区，或者拖进已经展开的绳子，就铺开晾衣台；拖出晾衣台就收起
        // 在绳上拖自己的衣服调整位置时，也铺开晾衣台，整块区域稳定地接住拖拽
        let isReordering = model.isDraggingOut && isButtonDown && model.isExpanded && inPanel
        var wantsShelf = isReordering || isDraggingFiles && (inTriggerZone || (model.isExpanded && inPanel))
        #if DEBUG
        wantsShelf = wantsShelf || debugForcesShelf
        #endif
        if wantsShelf != isShelfOpen { setShelfOpen(wantsShelf) }
        setHinting(isDraggingFiles && nearTop && !isShelfOpen && !model.isExpanded)
        if isShelfOpen { return }

        if model.isPinned {
            expand()
            return
        }

        let ropeTop = screen.visibleFrame.maxY
        let onCollapsedRope = withinScreenX && mouse.y <= ropeTop && mouse.y >= ropeTop - RopeMetrics.collapsedHeight - 2
        guard model.isExpanded else {
            if onCollapsedRope && !isButtonDown {
                hoverSince = hoverSince ?? .now
                if let hoverSince, Date.now.timeIntervalSince(hoverSince) > Self.hoverDelay { expand() }
            } else {
                hoverSince = nil
            }
            return
        }

        hoverSince = nil
        if let peekUntil, peekUntil > .now { return }
        if model.isMenuOpen || model.isCollecting || model.isDraggingOut || isOverRope(mouse) {
            outsideSince = nil
            return
        }
        outsideSince = outsideSince ?? .now
        if let outsideSince, Date.now.timeIntervalSince(outsideSince) > Self.leaveDelay { collapse() }
    }

    /// 只对拖文件、图片做反应；拖文字、拖浏览器标签页时不理会。
    private func carriesFiles(_ pasteboard: NSPasteboard) -> Bool {
        let changeCount = pasteboard.changeCount
        if changeCount != dragTypesChangeCount {
            dragTypesChangeCount = changeCount
            let types = Set(pasteboard.types ?? [])
            dragCarriesFiles = !types.isDisjoint(with: DropLoader.draggedTypes)
        }
        return dragCarriesFiles
    }

    private func isOverRope(_ mouse: NSPoint) -> Bool {
        let frame = panel.frame
        guard frame.insetBy(dx: 0, dy: -2).contains(mouse) else { return false }
        let layout = RopeLayout(width: frame.width, count: model.store.items.count, expanded: true)
        let x = mouse.x - frame.minX
        let depth = frame.maxY - mouse.y

        let nearRope = depth <= RopeMetrics.ropeBand + layout.sag
        let overClothes = layout.clothesRange?.contains(x) ?? false
        // 两端的按钮：右边收衣服，左边全部取下
        let overButtons = (x >= frame.width - RopeMetrics.sideReserve || x <= RopeMetrics.sideReserve)
            && depth <= layout.ropeY(at: x) + 56
        // 带“撤销”按钮的提示还在时，鼠标在面板里就别收起
        let hasActionToast = model.toast?.actionTitle != nil
        return nearRope || overClothes || overButtons || hasActionToast
    }
}
