import Foundation
import Testing

@MainActor
struct SortTests {
    private func makeStore() throws -> (Sandbox, RopeStore, [URL]) {
        let sandbox = try Sandbox()
        let names = ["b-歌词.srt", "a-封面.png", "c-片段.mp4", "d-人声.wav"]
        let files = try names.map { try sandbox.file($0) }
        // 修改时间：d 最新，b 最旧；创建时间：b 最新，d 最旧（系统不允许创建时间晚于修改时间）
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for (index, name) in ["b-歌词.srt", "a-封面.png", "c-片段.mp4", "d-人声.wav"].enumerated() {
            try FileManager.default.setAttributes(
                [.modificationDate: base.addingTimeInterval(Double(index) * 60),
                 .creationDate: base.addingTimeInterval(-Double(index + 1) * 100)],
                ofItemAtPath: sandbox.url(name).path)
        }
        let store = RopeStore(directory: sandbox.url("Support"))
        store.hang(files, origin: .dropped)
        return (sandbox, store, files)
    }

    @Test func sortsByKind() throws {
        let (_, store, _) = try makeStore()
        store.sort(by: .kind)
        #expect(store.items.map(\.kind) == [.video, .audio, .image, .document])
    }

    @Test func sortsByModifiedNewestFirst() throws {
        let (_, store, _) = try makeStore()
        store.sort(by: .modified)
        #expect(store.items.map(\.name) == ["d-人声.wav", "c-片段.mp4", "a-封面.png", "b-歌词.srt"])
    }

    @Test func sortsByCreatedNewestFirst() throws {
        let (_, store, _) = try makeStore()
        store.sort(by: .created)
        #expect(store.items.map(\.name) == ["b-歌词.srt", "a-封面.png", "c-片段.mp4", "d-人声.wav"])
    }

    @Test func sortsByNameAndKeepsMissingLast() throws {
        let (sandbox, store, _) = try makeStore()
        try FileManager.default.removeItem(at: sandbox.url("a-封面.png"))
        store.refreshMovedItems()
        store.sort(by: .name)
        #expect(store.items.map(\.name) == ["b-歌词.srt", "c-片段.mp4", "d-人声.wav", "a-封面.png"])
        #expect(RopeStore(directory: sandbox.url("Support")).items.map(\.name).first == "b-歌词.srt", "排序结果要存盘")
    }
}
