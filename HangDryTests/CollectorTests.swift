import Foundation
import Testing

struct CollectorTests {
    private func jobs(_ urls: [URL]) -> [Collector.Job] {
        urls.map { Collector.Job(id: UUID(), source: $0, kind: FileKind.classify($0), name: $0.lastPathComponent) }
    }

    @Test func movesScatteredFilesIntoKindFolders() throws {
        let sandbox = try Sandbox()
        let files = [
            try sandbox.file("Downloads/clip.mp4"),
            try sandbox.file("Desktop/人声干音.wav"),
            try sandbox.file("Desktop/封面.png"),
            try sandbox.file("Documents/MV/剪辑工程.prproj"),
            try sandbox.file("Documents/歌词.srt"),
        ]
        let destination = sandbox.url("归档")

        let report = Collector.run(jobs(files), into: destination) { _ in }

        #expect(report.failed.isEmpty)
        #expect(report.moved.count == 5)
        #expect(sandbox.exists("归档/视频/clip.mp4"))
        #expect(sandbox.exists("归档/音频/人声干音.wav"))
        #expect(sandbox.exists("归档/图片/封面.png"))
        #expect(sandbox.exists("归档/工程/剪辑工程.prproj"))
        #expect(sandbox.exists("归档/文档/歌词.srt"))
        for file in files {
            #expect(!FileManager.default.fileExists(atPath: file.path), "原文件应该被移走：\(file.lastPathComponent)")
        }
    }

    @Test func writesManifestWithOriginalPaths() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.file("Downloads/clip.mp4")
        let report = Collector.run(jobs([source]), into: sandbox.url("归档")) { _ in }

        let manifestURL = try #require(report.manifestURL)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let files = try #require(json["files"] as? [[String: Any]])
        #expect(files.count == 1)
        #expect(files.first?["from"] as? String == source.standardizedFileURL.path)
        #expect((files.first?["to"] as? String)?.hasSuffix("归档/视频/clip.mp4") == true)
    }

    @Test func appendsNumberWhenNameIsTaken() throws {
        let sandbox = try Sandbox()
        try sandbox.file("归档/视频/clip.mp4", contents: "old")
        let first = try sandbox.file("A/clip.mp4", contents: "new A")
        let second = try sandbox.file("B/clip.mp4", contents: "new B")

        let report = Collector.run(jobs([first, second]), into: sandbox.url("归档")) { _ in }

        #expect(report.failed.isEmpty)
        #expect(try String(contentsOf: sandbox.url("归档/视频/clip.mp4"), encoding: .utf8) == "old")
        #expect(try String(contentsOf: sandbox.url("归档/视频/clip 2.mp4"), encoding: .utf8) == "new A")
        #expect(try String(contentsOf: sandbox.url("归档/视频/clip 3.mp4"), encoding: .utf8) == "new B")
    }

    @Test func leavesFilesThatAreAlreadyInPlace() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.file("归档/视频/clip.mp4")
        let report = Collector.run(jobs([source]), into: sandbox.url("归档")) { _ in }

        #expect(report.moved.count == 1)
        #expect(sandbox.exists("归档/视频/clip.mp4"))
        #expect(!sandbox.exists("归档/视频/clip 2.mp4"))
    }

    @Test func reportsMissingSourcesAndKeepsGoing() throws {
        let sandbox = try Sandbox()
        let present = try sandbox.file("A/vocal.wav")
        let missing = sandbox.url("A/gone.mp4")

        let report = Collector.run(jobs([missing, present]), into: sandbox.url("归档")) { _ in }

        #expect(report.failed.map(\.name) == ["gone.mp4"])
        #expect(report.moved.count == 1)
        #expect(sandbox.exists("归档/音频/vocal.wav"))
    }

    @Test func reportsProgressForEveryJob() throws {
        let sandbox = try Sandbox()
        let files = try (1...4).map { try sandbox.file("A/\($0).png") }
        let counter = ProgressCounter()

        _ = Collector.run(jobs(files), into: sandbox.url("归档")) { counter.record($0) }

        #expect(counter.values == [1, 2, 3, 4])
    }
}

private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int] = []

    var values: [Int] { lock.withLock { recorded } }

    func record(_ value: Int) {
        lock.withLock { recorded.append(value) }
    }
}

struct CollectorLabelTests {
    @Test func usesLabelsWhenAsked() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.file("Downloads/IMG_4821.mov")
        let job = Collector.Job(id: UUID(), source: source, kind: .video, name: "IMG_4821.mov", label: "副歌 / 航拍 第二条")

        _ = Collector.run([job], into: sandbox.url("归档"), usingLabels: true) { _ in }

        #expect(sandbox.exists("归档/视频/副歌 - 航拍 第二条.mov"))
    }

    @Test func keepsOriginalNamesByDefault() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.file("Downloads/IMG_4821.mov")
        let job = Collector.Job(id: UUID(), source: source, kind: .video, name: "IMG_4821.mov", label: "副歌航拍")

        _ = Collector.run([job], into: sandbox.url("归档")) { _ in }

        #expect(sandbox.exists("归档/视频/IMG_4821.mov"))
    }

    @Test func doesNotDoubleTheExtension() {
        let job = Collector.Job(id: UUID(), source: URL(filePath: "/a/b.png"), kind: .image, name: "b.png", label: "封面.PNG")
        #expect(job.targetName(usingLabel: true) == "封面.PNG")
    }
}
