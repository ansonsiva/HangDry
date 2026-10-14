import SwiftUI

struct MenuBarContent: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model

        Toggle("显示晾衣绳", isOn: $model.isRopeVisible)
        Toggle("一直展开", isOn: $model.isPinned)
            .keyboardShortcut("h", modifiers: [.control, .option])

        Divider()

        Button("收衣服…") { model.collect() }
            .keyboardShortcut("k", modifiers: [.control, .option])
            .disabled(model.store.items.isEmpty || model.isCollecting)
        Button("全部取下") { model.takeDownAll() }
            .keyboardShortcut(.delete, modifiers: [.control, .option])
            .disabled(model.store.items.isEmpty || model.isCollecting)
        Menu("排序") {
            ForEach(Array(RopeStore.SortOrder.allCases.enumerated()), id: \.element) { index, order in
                Button(order.title) { model.sort(by: order) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.control, .option])
            }
        }
        .disabled(model.store.items.count < 2)
        if !model.unavailableShortcuts.isEmpty {
            Text("这些快捷键被别的 App 占用：\(model.unavailableShortcuts.joined(separator: " "))")
        }

        Divider()

        Toggle("拖到屏幕顶端时挂上", isOn: $model.isDragToHangEnabled)
        Toggle("自动挂上拷贝的文件和图片", isOn: $model.isWatchingClipboard)
        if model.isWatchingClipboard {
            switch model.clipboardPermission {
            case .denied:
                Button("⚠️ 剪贴板权限被拒绝，去系统设置开启…") { model.openClipboardSettings() }
            case .ask:
                Button("在系统设置里把剪贴板设为“始终允许”，免得每次询问…") { model.openClipboardSettings() }
            case .allowed:
                EmptyView()
            }
        }

        Divider()

        Menu("自动挂绳目录") {
            ForEach(model.watcher.folders) { folder in
                Menu(folder.name) {
                    Button("在 Finder 中显示") { model.revealWatchedFolder(folder) }
                    Button("停止监听") { model.watcher.remove(folder.id) }
                }
            }
            if !model.watcher.folders.isEmpty {
                Divider()
            }
            Button("添加目录…") { model.addWatchedFolder() }
        }

        Toggle("登录时启动", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.setLaunchAtLogin($0) }
        ))

        Divider()

        Button("退出 HangDry") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
