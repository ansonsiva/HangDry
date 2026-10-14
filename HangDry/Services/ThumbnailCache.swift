import AppKit
import QuickLookThumbnailing

/// 用 Quick Look 生成卡片缩略图（视频帧、图片、PDF 首页等），生成不了时用系统图标。
///
/// 按“哪件衣服 + 文件版本（路径、修改时间、大小）”缓存：
/// 同一个位置后来出现的同名新文件、或者被覆盖改过的文件，都会重新生成，不会沿用旧图。
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private struct Entry {
        let version: String
        let image: NSImage
    }

    private var entries: [UUID: Entry] = [:]

    func cached(for item: UUID) -> NSImage? { entries[item]?.image }

    func thumbnail(for url: URL, item: UUID) async -> NSImage? {
        let version = Self.version(of: url)
        if let entry = entries[item], entry.version == version { return entry.image }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 132, height: 116),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        entries[item] = Entry(version: version, image: image)
        return image
    }

    /// 衣服取下后不再需要它的缩略图
    func forget(_ items: some Sequence<UUID>) {
        for item in items { entries[item] = nil }
    }

    func dragImage(for url: URL, item: UUID) -> NSImage {
        cached(for: item) ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    private static func version(of url: URL) -> String {
        // URL 会缓存读过的文件属性，不清掉的话文件被覆盖后仍读到旧的修改时间
        var url = url
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(url.path)|\(modified)|\(values?.fileSize ?? -1)"
    }
}
