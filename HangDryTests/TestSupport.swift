import Foundation

/// 每个测试一个独立的临时目录。
struct Sandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "HangDryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ relativePath: String, contents: String = "hang dry") throws -> URL {
        let url = root.appending(path: relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func url(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relativePath).path)
    }
}
