import Foundation
import Testing
import UniformTypeIdentifiers

@MainActor
struct RopeStoreTests {
    @Test func hangsEachFileOnceAndPersists() throws {
        let sandbox = try Sandbox()
        let a = try sandbox.file("A/clip.mp4")
        let b = try sandbox.file("A/vocal.wav")
        let store = RopeStore(directory: sandbox.url("Support"))

        #expect(store.hang([a, b, a], origin: .dropped).count == 2)
        #expect(store.hang([a], origin: .watched).isEmpty)

        let reloaded = RopeStore(directory: sandbox.url("Support"))
        #expect(reloaded.items.map(\.name) == ["clip.mp4", "vocal.wav"])
        #expect(reloaded.items.map(\.kind) == [.video, .audio])
        #expect(reloaded.missing.isEmpty)
    }

    @Test func takeDownKeepsTheOriginalFile() throws {
        let sandbox = try Sandbox()
        let a = try sandbox.file("A/clip.mp4")
        let store = RopeStore(directory: sandbox.url("Support"))
        let ids = store.hang([a], origin: .dropped)

        store.takeDown(Set(ids))

        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: a.path))
    }

    @Test func copiesLiveInSupportFolderAndAreDeletedOnTakeDown() async throws {
        let sandbox = try Sandbox()
        let original = try sandbox.file("A/cover.png")
        let store = RopeStore(directory: sandbox.url("Support"))

        await store.hangCopies(of: [original])

        let item = try #require(store.items.first)
        let copy = try #require(store.url(for: item.id))
        #expect(item.isCopy)
        #expect(copy.path.hasPrefix(sandbox.url("Support/Copies").standardizedFileURL.path))
        #expect(FileManager.default.fileExists(atPath: copy.path))

        store.takeDown([item.id])

        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test func followsRenamedFiles() throws {
        let sandbox = try Sandbox()
        let a = try sandbox.file("A/clip.mp4")
        let store = RopeStore(directory: sandbox.url("Support"))
        let id = try #require(store.hang([a], origin: .dropped).first)

        try FileManager.default.moveItem(at: a, to: sandbox.url("B-renamed.mp4"))
        store.refreshMovedItems()

        #expect(store.item(for: id)?.name == "B-renamed.mp4")
        #expect(store.missing.isEmpty)
    }

    @Test func marksDeletedFilesAsMissing() throws {
        let sandbox = try Sandbox()
        let a = try sandbox.file("A/clip.mp4")
        let store = RopeStore(directory: sandbox.url("Support"))
        let id = try #require(store.hang([a], origin: .dropped).first)

        try FileManager.default.removeItem(at: a)
        store.refreshMovedItems()

        #expect(store.missing == [id])
        #expect(store.collectJobs().isEmpty)
    }

    @Test func collectingTakesMovedItemsOffTheRope() throws {
        let sandbox = try Sandbox()
        let a = try sandbox.file("A/clip.mp4")
        let b = try sandbox.file("A/vocal.wav")
        let store = RopeStore(directory: sandbox.url("Support"))
        store.hang([a, b], origin: .dropped)
        try FileManager.default.removeItem(at: b)
        store.refreshMovedItems()

        let report = Collector.run(store.collectJobs(), into: sandbox.url("归档")) { _ in }
        store.finishCollect(report)

        #expect(sandbox.exists("归档/视频/clip.mp4"))
        // 找不到的文件留在绳上，等用户处理
        #expect(store.items.map(\.name) == ["vocal.wav"])
    }

    @Test func insertsAtDropPosition() throws {
        let sandbox = try Sandbox()
        let files = try ["a.mp4", "b.wav", "c.png", "d.srt"].map { try sandbox.file("A/\($0)") }
        let store = RopeStore(directory: sandbox.url("Support"))
        store.hang(Array(files[0...1]), origin: .dropped)

        store.hang(Array(files[2...3]), origin: .dropped, at: 1)

        #expect(store.items.map(\.name) == ["a.mp4", "c.png", "d.srt", "b.wav"])
    }

    @Test func clipboardImagesAreSavedAsCopies() throws {
        let sandbox = try Sandbox()
        let store = RopeStore(directory: sandbox.url("Support"))
        let clip = try #require(ImageClip(data: Data([0x89, 0x50, 0x4E, 0x47]), type: .png))

        let id = try #require(store.hangImage(clip, named: "cover-art.png", origin: .pasted))

        let item = try #require(store.item(for: id))
        #expect(item.isCopy)
        #expect(item.kind == .image)
        #expect(item.name == "cover-art.png")
        #expect(try Data(contentsOf: try #require(store.url(for: id))) == clip.data)
    }
}

@MainActor
struct LabelTests {
    @Test func labelsPersistAndClear() throws {
        let sandbox = try Sandbox()
        let store = RopeStore(directory: sandbox.url("Support"))
        let id = try #require(store.hang([try sandbox.file("IMG_4821.mov")], origin: .dropped).first)

        store.setLabel("  副歌航拍  ", for: id)
        #expect(store.item(for: id)?.displayName == "副歌航拍")
        #expect(RopeStore(directory: sandbox.url("Support")).items.first?.label == "副歌航拍")

        store.setLabel("", for: id)
        #expect(store.item(for: id)?.label == nil)
        store.setLabel("IMG_4821.mov", for: id)
        #expect(store.item(for: id)?.label == nil, "和原文件名一样就不算备注名")
        #expect(FileManager.default.fileExists(atPath: sandbox.url("IMG_4821.mov").path), "原文件不动")
    }
}
