import Foundation
import Testing

struct FileKindTests {
    @Test(arguments: [
        ("clip.mp4", FileKind.video),
        ("take.MOV", .video),
        ("vocal.wav", .audio),
        ("beat.mp3", .audio),
        ("cover.png", .image),
        ("still.jpg", .image),
        ("lyrics.srt", .document),
        ("lyrics.lrc", .document),
        ("brief.pdf", .document),
        ("edit.prproj", .project),
        ("grade.drp", .project),
        ("comp.aep", .project),
        ("poster.psd", .project),
        ("assets.zip", .archive),
    ])
    func classifiesByExtension(name: String, expected: FileKind) {
        #expect(FileKind.classify(URL(filePath: "/nonexistent/\(name)")) == expected)
    }

    @Test func classifiesDirectories() throws {
        let sandbox = try Sandbox()
        try sandbox.file("素材/a.txt")
        #expect(FileKind.classify(sandbox.url("素材")) == .folder)
    }

    @Test func everyKindHasDistinctFolder() {
        let names = FileKind.allCases.map(\.folderName)
        #expect(Set(names).count == names.count)
    }
}
