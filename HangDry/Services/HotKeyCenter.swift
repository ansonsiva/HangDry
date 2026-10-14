import AppKit
import Carbon.HIToolbox

/// 全局快捷键：在任何 App 里按都有效。用系统的热键接口注册，不需要辅助功能权限，沙盒和 App Store 都允许。
@MainActor
final class HotKeyCenter {
    struct Shortcut {
        let keyCode: UInt32
        let modifiers: NSEvent.ModifierFlags
        /// 在菜单里显示用，比如 "H"
        let key: String

        var display: String {
            var text = ""
            if modifiers.contains(.control) { text += "⌃" }
            if modifiers.contains(.option) { text += "⌥" }
            if modifiers.contains(.shift) { text += "⇧" }
            if modifiers.contains(.command) { text += "⌘" }
            return text + key
        }

        fileprivate var carbonModifiers: UInt32 {
            var flags: UInt32 = 0
            if modifiers.contains(.control) { flags |= UInt32(controlKey) }
            if modifiers.contains(.option) { flags |= UInt32(optionKey) }
            if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
            if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
            return flags
        }
    }

    private var actions: [UInt32: () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// 注册一个快捷键；被别的 App 占用时返回 false。
    @discardableResult
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(), 0, &reference
        )
        guard status == noErr, let reference else { return false }
        references.append(reference)
        actions[id] = action
        return true
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        actions.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyCallback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// 'HgDy'
    nonisolated fileprivate static let signature: OSType = 0x4867_4479
}

/// 热键事件在主线程的事件循环里分发
private func hotKeyCallback(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
    let id = hotKeyID.id
    // 指针本身不能跨隔离传递，先转成地址值
    let address = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HotKeyCenter>.fromOpaque(pointer).takeUnretainedValue().fire(id)
    }
    return noErr
}

extension HotKeyCenter.Shortcut {
    static let toggleRope = Self(keyCode: UInt32(kVK_ANSI_H), modifiers: [.control, .option], key: "H")
    static let collect = Self(keyCode: UInt32(kVK_ANSI_K), modifiers: [.control, .option], key: "K")
    static let takeDownAll = Self(keyCode: UInt32(kVK_Delete), modifiers: [.control, .option], key: "⌫")
    static let sortByKind = Self(keyCode: UInt32(kVK_ANSI_1), modifiers: [.control, .option], key: "1")
    static let sortByCreated = Self(keyCode: UInt32(kVK_ANSI_2), modifiers: [.control, .option], key: "2")
    static let sortByModified = Self(keyCode: UInt32(kVK_ANSI_3), modifiers: [.control, .option], key: "3")
    static let sortByName = Self(keyCode: UInt32(kVK_ANSI_4), modifiers: [.control, .option], key: "4")

    static func sort(_ order: RopeStore.SortOrder) -> Self {
        switch order {
        case .kind: .sortByKind
        case .created: .sortByCreated
        case .modified: .sortByModified
        case .name: .sortByName
        }
    }
}
