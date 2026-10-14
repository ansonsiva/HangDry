import AppKit
import Testing

/// 同一个位置先后出现两个同名文件时，第二件衣服要用自己的缩略图。
@MainActor
struct ThumbnailCacheTests {
    private func writePNG(_ color: NSColor, to url: URL, size: Int = 64) throws {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    /// 缩略图正中间像素的红色分量
    private func redness(_ image: NSImage) throws -> CGFloat {
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let color = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        return color.redComponent
    }

    @Test func sameNameLaterFileGetsItsOwnThumbnail() async throws {
        let sandbox = try Sandbox()
        let url = sandbox.url("封面.png")
        let cache = ThumbnailCache.shared

        try writePNG(.red, to: url)
        let first = try #require(await cache.thumbnail(for: url, item: UUID()))

        // 原文件被收走后，同一位置又出现一个同名的新文件
        try FileManager.default.removeItem(at: url)
        try writePNG(.blue, to: url, size: 80)
        let second = try #require(await cache.thumbnail(for: url, item: UUID()))

        #expect(try redness(first) > 0.8)
        #expect(try redness(second) < 0.2)
    }

    @Test func overwrittenFileIsRegenerated() async throws {
        let sandbox = try Sandbox()
        let url = sandbox.url("渲染输出.png")
        let item = UUID()
        let cache = ThumbnailCache.shared

        try writePNG(.red, to: url)
        _ = await cache.thumbnail(for: url, item: item)
        try await Task.sleep(for: .milliseconds(20))
        try writePNG(.blue, to: url, size: 80)
        let refreshed = try #require(await cache.thumbnail(for: url, item: item))

        #expect(try redness(refreshed) < 0.2)
    }
}
