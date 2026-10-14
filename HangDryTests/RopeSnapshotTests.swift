import AppKit
import SwiftUI
import Testing

/// 把晾衣绳离屏渲染成 PNG，方便不开 App 也能检查界面。
/// 只在设置了 HANGDRY_SNAPSHOT_OUT 时运行：
///   TEST_RUNNER_HANGDRY_SNAPSHOT_IN=<测试素材目录> TEST_RUNNER_HANGDRY_SNAPSHOT_OUT=<输出目录> xcodebuild test ...
@MainActor
struct RopeSnapshotTests {
    private nonisolated static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["HANGDRY_SNAPSHOT_OUT"] != nil))
    func renderRopeStates() async throws {
        let output = URL(filePath: try #require(Self.environment["HANGDRY_SNAPSHOT_OUT"]), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sandbox = try Sandbox()

        // 空绳子
        let emptyModel = AppModel(store: RopeStore(directory: sandbox.url("Empty")))
        emptyModel.isExpanded = true
        try render(emptyModel, to: output.appending(path: "rope-empty.png"))

        // 挂上测试素材
        let store = RopeStore(directory: sandbox.url("Support"))
        if let input = Self.environment["HANGDRY_SNAPSHOT_IN"] {
            let files = try FileManager.default
                .contentsOfDirectory(at: URL(filePath: input), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            store.hang(files, origin: .dropped)
        }
        for item in store.items {
            if let url = store.url(for: item.id) { _ = await ThumbnailCache.shared.thumbnail(for: url, item: item.id) }
        }
        let model = AppModel(store: store)
        model.isExpanded = true
        model.selection = store.items.dropFirst().first.map { [$0.id] } ?? []
        try render(model, to: output.appending(path: "rope-expanded.png"))

        // 拖着 2 个文件停在第 2、3 件之间
        let between = (RopeLayout(width: Self.width, count: store.items.count, expanded: true).x(1)
            + RopeLayout(width: Self.width, count: store.items.count, expanded: true).x(2)) / 2
        model.dropUpdated(atX: between, width: Self.width, count: 2)
        try render(model, to: output.appending(path: "rope-drop-target.png"))
        model.dropExited()

        model.isExpanded = false
        model.selection = []
        try render(model, to: output.appending(path: "rope-collapsed.png"))

        model.isDragHinting = true
        try render(model, to: output.appending(path: "rope-drag-hint.png"))
        model.isDragHinting = false

        // 全部取下后，带撤销按钮的提示
        model.isExpanded = true
        model.takeDownAll()
        try render(model, to: output.appending(path: "rope-taken-down.png"))
        model.performToastAction()

        // 衣服很多时会叠在一起
        let crowdedStore = RopeStore(directory: sandbox.url("Crowded"))
        let extensions = ["mp4", "wav", "png", "srt", "prproj", "mov", "jpg", "pdf"]
        let crowdedFiles = try (1...36).map { try sandbox.file("crowded/素材\($0).\(extensions[$0 % extensions.count])") }
        crowdedStore.hang(crowdedFiles, origin: .watched)
        let crowdedModel = AppModel(store: crowdedStore)
        crowdedModel.isExpanded = true
        try render(crowdedModel, to: output.appending(path: "rope-crowded.png"))
    }

    private static let width: CGFloat = 1280

    private func render(_ model: AppModel, to url: URL) throws {
        let width = Self.width
        let view = ZStack(alignment: .top) {
            // 模拟桌面壁纸，方便看清透明区域
            LinearGradient(colors: [Color(red: 0.25, green: 0.36, blue: 0.55), Color(red: 0.62, green: 0.55, blue: 0.68)],
                           startPoint: .top, endPoint: .bottom)
            RopeView(model: model)
                .environment(\.rendersInteraction, false)
        }
        .frame(width: width, height: RopeMetrics.expandedHeight)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
