import AppKit
import Testing
import UniformTypeIdentifiers

/// 用独立命名的剪贴板测试，不碰系统剪贴板，也不会触发系统的剪贴板访问提示。
@MainActor
struct ClipboardTests {
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("HangDryTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func pngData() throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func copiedFilesBecomeFiles() throws {
        let sandbox = try Sandbox()
        let file = try sandbox.file("clip.mp4")
        let pasteboard = makePasteboard()
        pasteboard.writeObjects([file as NSURL])

        guard case .files(let urls) = ClipboardWatcher.content(of: pasteboard) else {
            Issue.record("应识别为文件")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["clip.mp4"])
    }

    @Test func copiedImageBecomesImage() throws {
        let pasteboard = makePasteboard()
        pasteboard.setData(try pngData(), forType: .png)
        pasteboard.setString("https://example.com/photos/cover-art.png?size=large", forType: .URL)

        guard case .image(let clip, let source) = ClipboardWatcher.content(of: pasteboard) else {
            Issue.record("应识别为图片")
            return
        }
        #expect(clip.fileExtension == "png")
        #expect(clip.fileName(sourceURL: source, prefix: "剪贴板图片") == "cover-art.png")
    }

    @Test func tiffIsConvertedToPNG() throws {
        let png = try pngData()
        let tiff = try #require(NSBitmapImageRep(data: png)?.tiffRepresentation)
        let pasteboard = makePasteboard()
        pasteboard.setData(tiff, forType: .tiff)

        guard case .image(let clip, _) = ClipboardWatcher.content(of: pasteboard) else {
            Issue.record("应识别为图片")
            return
        }
        #expect(clip.fileExtension == "png")
        #expect(NSBitmapImageRep(data: clip.data) != nil)
    }

    @Test func richTextWithPreviewImageIsIgnored() throws {
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.rtf, .tiff], owner: nil)
        pasteboard.setData(Data("{\\rtf1 hi}".utf8), forType: .rtf)
        pasteboard.setData(try #require(NSBitmapImageRep(data: try pngData())?.tiffRepresentation), forType: .tiff)

        #expect(ClipboardWatcher.content(of: pasteboard) == nil)
    }

    @Test func plainTextIsIgnored() {
        let pasteboard = makePasteboard()
        pasteboard.setString("歌词第一句", forType: .string)
        #expect(ClipboardWatcher.content(of: pasteboard) == nil)
    }

    @Test func concealedContentIsIgnored() throws {
        let sandbox = try Sandbox()
        let pasteboard = makePasteboard()
        pasteboard.declareTypes([.fileURL, .init("org.nspasteboard.ConcealedType")], owner: nil)
        pasteboard.setString(try sandbox.file("secret.txt").absoluteString, forType: .fileURL)
        pasteboard.setString("", forType: .init("org.nspasteboard.ConcealedType"))

        #expect(ClipboardWatcher.content(of: pasteboard) == nil)
    }

    @Test func imageFileNameFallsBackToPrefixAndTime() throws {
        let clip = try #require(ImageClip(data: try pngData(), type: .png))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-10T14:41:03Z"))
        let name = clip.fileName(sourceURL: nil, prefix: "剪贴板图片", date: date)
        #expect(name.hasPrefix("剪贴板图片 2026-10-10 "))
        #expect(name.hasSuffix(".png"))
    }
}

extension ClipboardWatcher.Content: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.files(a), .files(b)): a == b
        case let (.image(a, sa), .image(b, sb)): a == b && sa == sb
        default: false
        }
    }
}
