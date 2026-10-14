import AppKit
import Observation
import ServiceManagement
import SwiftUI
import os

/// 衣服离开绳子的方式：取下时往上飘走，收衣服时飞进篮子。
enum ClothesRemovalStyle {
    case liftOff
    case intoBasket
}

struct CollectProgress: Equatable {
    var done: Int
    let total: Int
}

/// 绳子下方的一句短提示，比如“挂上了 3 件”。`index` 指向它所说明的那件衣服。
struct RopeToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let index: Int?
    /// 提示上的按钮，比如“撤销”
    var actionTitle: String?
}

/// App 的中枢：持有绳上的数据、目录监听、界面状态，并处理菜单和卡片上的操作。
@MainActor
@Observable
final class AppModel {
    let store: RopeStore
    let watcher = FolderWatcher()

    var isExpanded = false {
        didSet { if isExpanded && !oldValue { expandCount += 1 } }
    }
    /// 绳子展开过几次；卡片借此重新检查缩略图是否过期
    private(set) var expandCount = 0
    var isMenuOpen = false
    var selection: Set<UUID> = []
    /// 鼠标正停在哪件衣服上
    private(set) var hoveredID: UUID?
    private(set) var collectProgress: CollectProgress?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var toast: RopeToast?
    private(set) var removalStyle = ClothesRemovalStyle.liftOff
    /// 衣服飞进篮子时加一，篮子弹一下
    private(set) var basketBounce = 0

    // MARK: 拖进来

    /// 文件或图片被拖到了屏幕顶部，晾衣台已经铺开（由面板轮询设置）。
    var isDragActive = false
    /// 拖着文件靠近屏幕上方、绳子还收着：垂下一个小标签，提示往这里拖。
    var isDragHinting = false
    /// 正在拖动绳上的哪些衣服（拖出去，或在绳上调整位置）
    private(set) var draggedIDs: Set<UUID> = []
    var isDraggingOut: Bool { !draggedIDs.isEmpty }
    /// 拖到面板上时，给新衣服预留的位置（插在第几件之前）。
    private(set) var dropGapIndex: Int?
    private(set) var dropCount = 0
    var isDropTargeted: Bool { dropGapIndex != nil }

    // MARK: 设置

    var isRopeVisible = true {
        didSet { panelController?.setVisible(isRopeVisible) }
    }

    var isPinned = UserDefaults.standard.bool(forKey: "isPinned") {
        didSet {
            guard isPinned != oldValue else { return }
            UserDefaults.standard.set(isPinned, forKey: "isPinned")
            panelController?.pinnedChanged(isPinned)
        }
    }

    /// 拖文件到屏幕顶端时弹出晾衣台。关掉后只能靠拷贝或自动挂绳目录挂文件。
    var isDragToHangEnabled = UserDefaults.standard.object(forKey: "isDragToHangEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isDragToHangEnabled, forKey: "isDragToHangEnabled") }
    }

    var isWatchingClipboard = UserDefaults.standard.object(forKey: "isWatchingClipboard") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isWatchingClipboard, forKey: "isWatchingClipboard")
            updateClipboardWatcher()
        }
    }

    /// 系统对本 App 读剪贴板的授权状态（macOS 15.4 起）。
    private(set) var clipboardPermission = ClipboardPermission.current

    var isCollecting: Bool { collectProgress != nil }

    @ObservationIgnored private var panelController: RopePanelController?
    @ObservationIgnored private var toastAction: (() -> Void)?
    @ObservationIgnored private var pendingTakeDown: RopeStore.Detached?
    @ObservationIgnored private let clipboard = ClipboardWatcher()
    @ObservationIgnored private let hotKeys = HotKeyCenter()
    /// 被别的 App 占用、没注册上的快捷键
    private(set) var unavailableShortcuts: [String] = []
    @ObservationIgnored private let menuTracker = MenuTracker()
    @ObservationIgnored private let logger = Logger(subsystem: "com.huck.HangDry", category: "app")

    init(store: RopeStore = RopeStore()) {
        self.store = store
    }

    func start() {
        menuTracker.onChange = { [weak self] isOpen in self?.isMenuOpen = isOpen }
        watcher.onNewFiles = { [weak self] urls in
            self?.hangAutomatically(urls, origin: .watched) { String(localized: "自动挂上 \($0) 件") }
        }
        watcher.start()

        clipboard.onContent = { [weak self] content in self?.hangClipboard(content) }
        updateClipboardWatcher()

        let controller = RopePanelController(model: self)
        panelController = controller
        controller.show()
        controller.peek()
        registerHotKeys()

        #if DEBUG
        // 性能测量用：启动完成后再展开一次，单独看动画的开销
        // 性能测量用：铺开晾衣台并显示虚线衣服 6 秒，模拟拖着文件停在绳上
        if ProcessInfo.processInfo.arguments.contains("-demoShelf") {
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .seconds(4))
                panelController?.debugForcesShelf = true
                try? await Task.sleep(for: .seconds(0.3))
                let width = NSScreen.screens.first?.frame.width ?? 1440
                dropUpdated(atX: width / 2, width: width, count: 1)
                try? await Task.sleep(for: .seconds(6))
                dropExited()
                panelController?.debugForcesShelf = false
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-demoAnimation") {
            Task { [weak self] in
                for _ in 0..<3 {
                    try? await Task.sleep(for: .seconds(4))
                    self?.panelController?.collapse()
                    try? await Task.sleep(for: .seconds(1))
                    self?.panelController?.peek(for: 3)
                }
            }
        }
        #endif
    }

    // MARK: - 拖到绳上

    /// 拖着文件在晾衣台上移动：按光标位置算出插入点，绳子在那里坠下去并空出位置。
    func dropUpdated(atX x: CGFloat, width: CGFloat, count: Int) {
        let layout = RopeLayout(width: width, count: store.items.count, expanded: true)
        let index = layout.insertionIndex(at: x)
        guard index != dropGapIndex || count != dropCount else { return }
        if index != dropGapIndex {
            let pattern: NSHapticFeedbackManager.FeedbackPattern = dropGapIndex == nil ? .levelChange : .alignment
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
        withAnimation(.spring(duration: 0.32, bounce: 0.4)) {
            dropGapIndex = index
            dropCount = count
        }
    }

    func dropExited() {
        guard dropGapIndex != nil else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.35)) {
            dropGapIndex = nil
            dropCount = 0
        }
    }

    func beginDraggingClothes(_ ids: Set<UUID>) {
        draggedIDs = ids
    }

    func endDraggingClothes() {
        draggedIDs = []
        dropExited()
    }

    /// 在晾衣台上松开自己拖着的衣服：挪到空出来的位置。
    func performReorder() {
        guard let index = dropGapIndex, !draggedIDs.isEmpty else { return }
        let ids = draggedIDs
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
            store.move(ids, to: index)
            dropGapIndex = nil
            dropCount = 0
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// 松手：挂进预留的位置。文件只记链接（按住 ⌥ 挂副本）；浏览器等拖出来的图片存成副本。
    /// 在 `performDragOperation` 里同步调用：文件承诺必须在这一刻发起接收，之后只异步等结果。
    func performDrop(_ payload: DropPayload?) {
        let index = dropGapIndex ?? store.items.count
        let asCopy = NSEvent.modifierFlags.contains(.option)
        let promised: PromisedFiles?
        if case .promises(let receivers)? = payload {
            promised = DropLoader.startReceiving(receivers) { [store] in store.makeCopyFolder() }
        } else {
            promised = nil
        }
        Task {
            var files: [URL] = []
            var isCopy = asCopy
            var image: (ImageClip, URL?)?
            switch payload {
            case .files(let urls):
                files = asCopy ? await store.makeCopies(of: urls) : urls
            case .promises:
                isCopy = true
                files = await promised?.value() ?? []
            case .image(let clip, let source):
                image = (clip, source)
            case nil:
                break
            }

            var added: [UUID] = []
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
                added = store.hang(files, origin: .dropped, isCopy: isCopy, at: index)
                if let (clip, source) = image,
                   let id = store.hangImage(clip, named: clip.fileName(sourceURL: source, prefix: String(localized: "拖入图片")), origin: .dropped, at: index) {
                    added.append(id)
                }
                dropGapIndex = nil
                dropCount = 0
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            let text: String
            if !added.isEmpty {
                text = String(localized: "挂上了 \(added.count) 件")
            } else if case .files? = payload {
                text = String(localized: "已经在绳上了")
            } else {
                text = String(localized: "没有可以挂的文件")
            }
            showToast(text, index: index)
        }
    }

    // MARK: - 自动挂上

    private func updateClipboardWatcher() {
        if isWatchingClipboard {
            clipboard.start()
        } else {
            clipboard.stop()
        }
        clipboardPermission = .current
    }

    private func hangClipboard(_ content: ClipboardWatcher.Content) {
        clipboardPermission = .current
        switch content {
        case .files(let urls):
            hangAutomatically(urls, origin: .pasted) { String(localized: "从剪贴板挂上 \($0) 件") }
        case .image(let clip, let source):
            var id: UUID?
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
                id = store.hangImage(clip, named: clip.fileName(sourceURL: source, prefix: String(localized: "剪贴板图片")), origin: .pasted)
            }
            guard id != nil else { return }
            panelController?.peek()
            showToast(String(localized: "从剪贴板挂上 1 张图片"), index: store.items.count - 1)
        }
    }

    private func hangAutomatically(_ urls: [URL], origin: HungItem.Origin, toast: (Int) -> String) {
        var added: [UUID] = []
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
            added = store.hang(urls, origin: origin)
        }
        guard let first = added.first else { return }
        panelController?.peek()
        showToast(toast(added.count), index: store.items.firstIndex { $0.id == first })
    }

    private func showToast(_ text: String, index: Int?, actionTitle: String? = nil,
                           duration: TimeInterval = 1.8, action: (() -> Void)? = nil) {
        let toast = RopeToast(text: text, index: index, actionTitle: actionTitle)
        toastAction = action
        withAnimation(.spring(duration: 0.3, bounce: 0.3)) { self.toast = toast }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, self.toast?.id == toast.id else { return }
            toastAction = nil
            withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
        }
    }

    func performToastAction() {
        let action = toastAction
        toastAction = nil
        withAnimation(.easeOut(duration: 0.2)) { toast = nil }
        action?()
    }

    // MARK: - 改名

    /// 改备注名：只改绳上显示的名字，原文件不动。
    func rename(_ id: UUID) {
        guard let item = store.item(for: id) else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "改名")
        alert.informativeText = String(localized: "只改晾衣绳上显示的名字，原文件不动。收衣服时可以选择用这个名字给文件命名。\n\n原文件名：\(item.name)")
        let field = NSTextField(string: item.displayName)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        field.lineBreakMode = .byTruncatingMiddle
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "好"))
        alert.addButton(withTitle: String(localized: "取消"))
        if item.label != nil { alert.addButton(withTitle: String(localized: "恢复原名")) }
        alert.window.initialFirstResponder = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.setLabel(field.stringValue, for: id)
        case .alertThirdButtonReturn:
            store.setLabel(nil, for: id)
        default:
            break
        }
    }

    // MARK: - 排序

    /// 一次性重新排好，衣服滑到新位置；之后新挂上的照常放在拖到的位置。
    func sort(by order: RopeStore.SortOrder) {
        guard store.items.count > 1 else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
            store.sort(by: order)
        }
        panelController?.peek(for: 2.5)
        showToast(order.doneMessage, index: nil)
    }

    // MARK: - 快捷键

    @ObservationIgnored private var lastPinToggle = Date.distantPast

    /// ⌃⌥H 切换“一直展开”。0.25 秒内的重复触发只算一次。
    func togglePinned() {
        guard Date.now.timeIntervalSince(lastPinToggle) > 0.25 else { return }
        lastPinToggle = .now
        isPinned.toggle()
    }

    private func registerHotKeys() {
        var unavailable: [String] = []
        func register(_ shortcut: HotKeyCenter.Shortcut, _ action: @escaping () -> Void) {
            if !hotKeys.register(shortcut, action: action) { unavailable.append(shortcut.display) }
        }
        register(.toggleRope) { [weak self] in self?.togglePinned() }
        register(.collect) { [weak self] in self?.collect() }
        register(.takeDownAll) { [weak self] in self?.takeDownAll() }
        for order in RopeStore.SortOrder.allCases {
            register(.sort(order)) { [weak self] in self?.sort(by: order) }
        }
        unavailableShortcuts = unavailable
    }

    // MARK: - 全部取下

    /// 把绳上所有链接都取下来，原文件不动。5 秒内可以撤销；副本文件等撤销时间过了才删除。
    func takeDownAll() {
        let ids = Set(store.items.map(\.id))
        guard !ids.isEmpty else { return }
        finishPendingTakeDown()

        var detached: RopeStore.Detached?
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            detached = store.detach(ids)
        }
        guard let detached else { return }
        selection = []
        pendingTakeDown = detached

        let undoWindow: TimeInterval = 5
        panelController?.peek(for: undoWindow)
        showToast(String(localized: "已全部取下 \(detached.count) 件"), index: nil, actionTitle: String(localized: "撤销"), duration: undoWindow) { [weak self] in
            self?.undoTakeDownAll()
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(undoWindow))
            guard let self, pendingTakeDown?.id == detached.id else { return }
            finishPendingTakeDown()
        }
    }

    private func undoTakeDownAll() {
        guard let detached = pendingTakeDown else { return }
        pendingTakeDown = nil
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) {
            store.restore(detached)
        }
        showToast(String(localized: "已放回 \(detached.count) 件"), index: nil)
    }

    /// 撤销时间过了（或 App 要退出）：真正清理副本和访问权限。
    func finishPendingTakeDown() {
        guard let detached = pendingTakeDown else { return }
        pendingTakeDown = nil
        store.discard(detached)
    }

    func openClipboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 选中与拖出

    func select(_ id: UUID, extending: Bool) {
        if extending {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if selection != [id] {
            selection = [id]
        }
    }

    func setHovered(_ id: UUID, _ isHovering: Bool) {
        if isHovering {
            if hoveredID != id { hoveredID = id }
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    /// 操作对象：点中的卡片属于多选时作用于全部选中项，否则只作用于它自己。
    func targets(for id: UUID) -> Set<UUID> {
        selection.contains(id) ? selection : [id]
    }

    /// 要拖出去的衣服和它们的文件，按绳上的先后顺序
    func dragItems(from id: UUID) -> [(id: UUID, url: URL)] {
        let ids = targets(for: id)
        return store.items
            .filter { ids.contains($0.id) && !store.missing.contains($0.id) }
            .compactMap { item in store.url(for: item.id).map { (item.id, $0) } }
    }

    // MARK: - 卡片操作

    func open(_ ids: Set<UUID>) {
        for url in urls(for: ids) { NSWorkspace.shared.open(url) }
    }

    func reveal(_ ids: Set<UUID>) {
        NSWorkspace.shared.activateFileViewerSelecting(urls(for: ids))
    }

    func takeDown(_ ids: Set<UUID>) {
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            store.takeDown(ids)
        }
        selection.subtract(ids)
    }

    func trash(_ ids: Set<UUID>) {
        let failures = withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
            store.trash(ids)
        }
        selection.subtract(ids)
        if !failures.isEmpty {
            showAlert(String(localized: "有 \(failures.count) 个文件没能移到废纸篓"), detail: failures.prefix(8).joined(separator: "\n"))
        }
    }

    func contextMenu(for id: UUID) -> NSMenu {
        if !selection.contains(id) { selection = [id] }
        let ids = targets(for: id)
        let count = ids.count
        let hasCopy = ids.contains { store.item(for: $0)?.isCopy == true }

        let menu = NSMenu()
        menu.delegate = menuTracker
        menu.addItem(ActionMenuItem(count > 1 ? String(localized: "打开（\(count) 项）") : String(localized: "打开")) { [weak self] in self?.open(ids) })
        menu.addItem(ActionMenuItem(String(localized: "在 Finder 中显示")) { [weak self] in self?.reveal(ids) })
        if ids.count == 1 {
            menu.addItem(ActionMenuItem(String(localized: "改名…")) { [weak self] in
                Task { @MainActor in self?.rename(id) }
            })
        }
        menu.addItem(.separator())
        let takeDownTitle = switch (count > 1, hasCopy) {
        case (false, false): String(localized: "从绳上取下")
        case (true, false): String(localized: "从绳上取下（\(count) 项）")
        case (false, true): String(localized: "从绳上取下（副本一并删除）")
        case (true, true): String(localized: "从绳上取下（\(count) 项，副本一并删除）")
        }
        menu.addItem(ActionMenuItem(takeDownTitle) { [weak self] in
            self?.takeDown(ids)
        })
        let trashTitle = count > 1 ? String(localized: "删除文件（\(count) 项，移到废纸篓）") : String(localized: "删除文件（移到废纸篓）")
        menu.addItem(ActionMenuItem(trashTitle) { [weak self] in self?.trash(ids) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(String(localized: "收衣服…")) { [weak self] in
            Task { @MainActor in self?.collect() }
        })
        menu.addItem(ActionMenuItem(String(localized: "全部取下")) { [weak self] in self?.takeDownAll() })
        menu.addItem(.separator())
        let sortItem = NSMenuItem(title: String(localized: "排序"), action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for order in RopeStore.SortOrder.allCases {
            sortMenu.addItem(ActionMenuItem(order.title) { [weak self] in self?.sort(by: order) })
        }
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)
        return menu
    }

    private func urls(for ids: Set<UUID>) -> [URL] {
        store.items
            .filter { ids.contains($0.id) && !store.missing.contains($0.id) }
            .compactMap { store.url(for: $0.id) }
    }

    // MARK: - 收衣服

    func collect() {
        guard !isCollecting else { return }
        let jobs = store.collectJobs()
        guard !jobs.isEmpty else {
            showAlert(String(localized: "绳上没有可以收的文件"), detail: String(localized: "先把文件拖到晾衣绳上。"))
            return
        }

        panelController?.collapse()
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = String(localized: "收衣服")
        panel.message = String(localized: "选择归档目录，绳上的 \(jobs.count) 个文件会按类型（视频、音频、图片、文档、工程…）移动进去")
        panel.prompt = String(localized: "收进这里")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let labelOption = NSButton(checkboxWithTitle: String(localized: "用备注名给文件命名"), target: nil, action: nil)
        labelOption.state = .on
        let hasLabels = jobs.contains { $0.label != nil }
        if hasLabels {
            panel.accessoryView = labelOption
            panel.isAccessoryViewDisclosed = true
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let usingLabels = hasLabels && labelOption.state == .on

        Task {
            await runCollect(jobs, into: destination, usingLabels: usingLabels)
        }
    }

    private func runCollect(_ jobs: [Collector.Job], into destination: URL, usingLabels: Bool) async {
        // 先换成“飞进篮子”的离开方式，再展开绳子让人看到进度
        removalStyle = .intoBasket
        collectProgress = CollectProgress(done: 0, total: jobs.count)
        panelController?.peek(for: 1)
        let model = self
        let report = await Task.detached(priority: .userInitiated) {
            Collector.run(jobs, into: destination, usingLabels: usingLabels) { done in
                Task { @MainActor in model.collectProgress?.done = done }
            }
        }.value

        collectProgress = nil
        let flight = min(0.6 + Double(report.moved.count) * 0.04, 1.8)
        panelController?.peek(for: flight + 4)
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            store.finishCollect(report)
        }
        selection.subtract(report.moved.map(\.id))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.45))
            self?.basketBounce += 1
        }
        try? await Task.sleep(for: .seconds(flight))
        removalStyle = .liftOff

        if report.failed.isEmpty {
            let destination = report.destination
            showToast(String(localized: "收好了 \(report.moved.count) 件"), index: nil, actionTitle: String(localized: "在 Finder 中显示"), duration: 4) {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } else {
            showCollectSummary(report)
        }
    }

    private func showCollectSummary(_ report: Collector.Report) {
        let alert = NSAlert()
        if report.failed.isEmpty {
            alert.messageText = String(localized: "收好了 \(report.moved.count) 个文件")
            alert.informativeText = String(localized: "归档位置：\(report.destination.path)")
        } else {
            alert.messageText = String(localized: "收好了 \(report.moved.count) 个，\(report.failed.count) 个没收成")
            let lines = report.failed.prefix(6).map { String(localized: "• \($0.name)：\($0.reason)") }
            alert.informativeText = (lines + ["", String(localized: "没收成的文件还挂在绳上。")]).joined(separator: "\n")
        }
        alert.addButton(withTitle: String(localized: "在 Finder 中显示"))
        alert.addButton(withTitle: String(localized: "好"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([report.destination])
        }
    }

    // MARK: - 自动挂绳目录

    func addWatchedFolder() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = String(localized: "自动挂绳目录")
        panel.message = String(localized: "这个目录里新出现的文件，写入完成后会自动挂到晾衣绳上")
        panel.prompt = String(localized: "监听这个目录")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "目录里已有的文件也挂上去吗？")
        alert.informativeText = String(localized: "之后新出现的文件都会自动挂上。")
        alert.addButton(withTitle: String(localized: "只挂新文件"))
        alert.addButton(withTitle: String(localized: "全部挂上"))
        let includeExisting = alert.runModal() == .alertSecondButtonReturn
        watcher.add(url, includeExisting: includeExisting)
    }

    func revealWatchedFolder(_ folder: FolderWatcher.Folder) {
        guard let url = watcher.url(for: folder) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 设置

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("登录启动设置失败：\(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func showAlert(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }
}

/// 右键菜单打开期间不收起晾衣绳。
@MainActor
private final class MenuTracker: NSObject, NSMenuDelegate {
    var onChange: ((Bool) -> Void)?

    func menuWillOpen(_ menu: NSMenu) { onChange?(true) }
    func menuDidClose(_ menu: NSMenu) { onChange?(false) }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() { handler() }
}
