import Foundation
import Testing

@MainActor
struct TakeDownAllTests {
    @Test func takesEverythingDownAndKeepsOriginals() throws {
        let sandbox = try Sandbox()
        let files = try ["a.mp4", "b.wav", "c.png"].map { try sandbox.file("A/\($0)") }
        let store = RopeStore(directory: sandbox.url("Support"))
        store.hang(files, origin: .dropped)
        let model = AppModel(store: store)

        model.takeDownAll()

        #expect(store.items.isEmpty)
        #expect(RopeStore(directory: sandbox.url("Support")).items.isEmpty, "取下的结果要存盘")
        for file in files {
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
        #expect(model.toast?.actionTitle == "撤销")
    }

    @Test func undoPutsEverythingBackInOrder() throws {
        let sandbox = try Sandbox()
        let files = try ["a.mp4", "b.wav", "c.png"].map { try sandbox.file("A/\($0)") }
        let store = RopeStore(directory: sandbox.url("Support"))
        store.hang(files, origin: .dropped)
        let model = AppModel(store: store)

        model.takeDownAll()
        model.performToastAction()

        #expect(store.items.map(\.name) == ["a.mp4", "b.wav", "c.png"])
        #expect(store.items.allSatisfy { store.url(for: $0.id) != nil })
        #expect(RopeStore(directory: sandbox.url("Support")).items.count == 3)
    }

    @Test func copiesSurviveUntilUndoWindowEnds() async throws {
        let sandbox = try Sandbox()
        let store = RopeStore(directory: sandbox.url("Support"))
        let clip = try #require(ImageClip(data: Data([1, 2, 3]), type: .png))
        let id = try #require(store.hangImage(clip, named: "剪贴板图片.png", origin: .pasted))
        let copy = try #require(store.url(for: id))
        let model = AppModel(store: store)

        model.takeDownAll()
        #expect(FileManager.default.fileExists(atPath: copy.path), "撤销时间内副本还在")

        model.finishPendingTakeDown()
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
    }

    @Test func secondTakeDownFinishesThePreviousOne() throws {
        let sandbox = try Sandbox()
        let store = RopeStore(directory: sandbox.url("Support"))
        let clip = try #require(ImageClip(data: Data([1, 2, 3]), type: .png))
        let firstID = try #require(store.hangImage(clip, named: "1.png", origin: .pasted))
        let firstCopy = try #require(store.url(for: firstID))
        let model = AppModel(store: store)
        model.takeDownAll()

        store.hang([try sandbox.file("A/b.wav")], origin: .dropped)
        model.takeDownAll()
        model.performToastAction()

        // 撤销只放回第二次取下的内容，第一次的副本已经清理
        #expect(store.items.map(\.name) == ["b.wav"])
        #expect(!FileManager.default.fileExists(atPath: firstCopy.path))
    }
}
