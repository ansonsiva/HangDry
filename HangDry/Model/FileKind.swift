import Foundation
import UniformTypeIdentifiers

/// 文件归类：决定卡片的图标颜色，以及收衣服时放进哪个子文件夹。
enum FileKind: String, Codable, Sendable, CaseIterable {
    case video, audio, image, document, project, archive, folder, other

    var folderName: String {
        switch self {
        case .video: String(localized: "视频")
        case .audio: String(localized: "音频")
        case .image: String(localized: "图片")
        case .document: String(localized: "文档")
        case .project: String(localized: "工程")
        case .archive: String(localized: "压缩包")
        case .folder: String(localized: "文件夹")
        case .other: String(localized: "其他")
        }
    }

    var symbolName: String {
        switch self {
        case .video: "film"
        case .audio: "waveform"
        case .image: "photo"
        case .document: "doc.text"
        case .project: "slider.horizontal.3"
        case .archive: "archivebox"
        case .folder: "folder"
        case .other: "doc"
        }
    }

    /// 剪辑、调色、合成、编曲、设计软件的工程文件，优先于系统类型判断。
    private static let projectExtensions: Set<String> = [
        "prproj", "prel", "drp", "drt", "dra", "aep", "aepx", "aet",
        "fcpxml", "fcpxmld", "fcpbundle", "motn", "moef",
        "logicx", "band", "als", "flp", "ptx", "cpr", "rpp", "sesx", "veg",
        "psd", "psb", "ai", "blend", "c4d", "kra", "procreate", "sketch", "fig", "otio", "edl",
    ]

    /// 文稿、表格、字幕、歌词。
    private static let documentExtensions: Set<String> = [
        "txt", "md", "rtf", "pdf", "doc", "docx", "pages", "key", "numbers",
        "xls", "xlsx", "ppt", "pptx", "csv", "srt", "ass", "ssa", "vtt", "lrc", "sbv",
    ]

    static func classify(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        if projectExtensions.contains(ext) { return .project }
        if documentExtensions.contains(ext) { return .document }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
        if values?.isDirectory == true, values?.isPackage != true { return .folder }

        guard let type = values?.contentType ?? UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .text) || type.conforms(to: .compositeContent) { return .document }
        return .other
    }
}
