import AppKit
import SwiftUI
import Testing

@MainActor
struct DropTests {
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("HangDryTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    /// SwiftUI 那一层不能注册拖放类型，否则拖拽会被它截住，到不了外层的 RopeContainerView。
    @Test func swiftUILayerLeavesDropsToContainer() throws {
        let sandbox = try Sandbox()
        let model = AppModel(store: RopeStore(directory: sandbox.url("Support")))
        let host = FirstMouseHostingView(rootView: RopeView(model: model))
        let container = RopeContainerView(host: host)
        container.frame = NSRect(x: 0, y: 0, width: 1200, height: RopeMetrics.expandedHeight)
        container.layoutSubtreeIfNeeded()

        #expect(host.registeredDraggedTypes.isEmpty)
        #expect(container.registeredDraggedTypes.contains(.fileURL))
        #expect(container.registeredDraggedTypes.contains(.png))
    }

    @Test func readsDraggedFiles() throws {
        let sandbox = try Sandbox()
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([try sandbox.file("a.mp4") as NSURL, try sandbox.file("b.wav") as NSURL])

        guard case .files(let urls)? = DropLoader.read(pasteboard) else {
            Issue.record("应读出文件")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["a.mp4", "b.wav"])
    }

    @Test func readsDraggedImageData() throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pasteboard = makePasteboard()
        pasteboard.setData(try #require(rep.tiffRepresentation), forType: .tiff)

        guard case .image(let clip, _)? = DropLoader.read(pasteboard) else {
            Issue.record("应读出图片")
            return
        }
        #expect(clip.fileExtension == "png")
    }

    @Test func ignoresDraggedText() {
        let pasteboard = makePasteboard()
        pasteboard.setString("一段歌词", forType: .string)
        #expect(DropLoader.read(pasteboard) == nil)
    }

    @Test func dropPositionOpensGapAndHangsThere() throws {
        let sandbox = try Sandbox()
        let store = RopeStore(directory: sandbox.url("Support"))
        store.hang(try ["a.mp4", "b.wav"].map { try sandbox.file($0) }, origin: .dropped)
        let model = AppModel(store: store)
        let layout = RopeLayout(width: 1200, count: 2, expanded: true)

        model.dropUpdated(atX: layout.x(0) - 50, width: 1200, count: 1)
        #expect(model.dropGapIndex == 0)
        model.dropUpdated(atX: (layout.x(0) + layout.x(1)) / 2, width: 1200, count: 1)
        #expect(model.dropGapIndex == 1)
        model.dropExited()
        #expect(model.dropGapIndex == nil)
    }
}

extension DropPayload: Equatable {
    public static func == (lhs: DropPayload, rhs: DropPayload) -> Bool {
        switch (lhs, rhs) {
        case let (.files(a), .files(b)): a == b
        case let (.image(a, sa), .image(b, sb)): a == b && sa == sb
        case let (.promises(a), .promises(b)): a == b
        default: false
        }
    }
}
