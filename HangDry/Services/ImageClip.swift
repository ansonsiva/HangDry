import AppKit
import UniformTypeIdentifiers

/// 剪贴板或拖拽里的图片数据（没有对应文件，比如浏览器里“拷贝图像”、截图到剪贴板）。
/// 挂上去时会存成一个副本文件。
struct ImageClip: Sendable, Equatable {
    let data: Data
    let fileExtension: String

    /// 按优先级尝试的图片类型；保留原始编码，TIFF 转成 PNG。
    static let preferredTypes: [UTType] = [.png, .jpeg, .gif, .heic, .webP, .tiff]

    init?(data: Data, type: UTType) {
        if type.conforms(to: .tiff) {
            guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
            self.data = png
            fileExtension = "png"
        } else {
            guard !data.isEmpty else { return nil }
            self.data = data
            fileExtension = type.preferredFilenameExtension ?? "png"
        }
    }

    /// 生成文件名：优先沿用图片来源网址里的文件名，否则用“前缀 + 时间”命名。
    func fileName(sourceURL: URL?, prefix: String, date: Date = .now) -> String {
        if let sourceURL {
            let base = (sourceURL.lastPathComponent as NSString).deletingPathExtension
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.isEmpty, base != "/", base.count <= 80 {
                return "\(base).\(fileExtension)"
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).\(fileExtension)"
    }
}

extension ImageClip {
    /// 从剪贴板读取图片。带 RTF 的是从文稿类 App 拷贝的文字，那里附带的图片只是排版预览，跳过。
    /// 同时返回图片的来源网址（浏览器会一并写入），用来给文件命名。
    @MainActor
    static func read(from pasteboard: NSPasteboard) -> (ImageClip, URL?)? {
        let types = Set(pasteboard.types ?? [])
        guard !types.contains(.rtf) else { return nil }
        for type in preferredTypes {
            let pasteboardType = NSPasteboard.PasteboardType(type.identifier)
            guard types.contains(pasteboardType),
                  let data = pasteboard.data(forType: pasteboardType),
                  let clip = ImageClip(data: data, type: type) else { continue }
            return (clip, pasteboard.string(forType: .URL).flatMap(URL.init(string:)))
        }
        return nil
    }
}

/// 系统对本 App 读剪贴板的授权状态。
enum ClipboardPermission {
    /// 还没问过，或每次都会弹窗询问
    case ask
    case allowed
    case denied

    @MainActor
    static var current: ClipboardPermission {
        guard #available(macOS 15.4, *) else { return .allowed }
        switch NSPasteboard.general.accessBehavior {
        case .alwaysAllow: return .allowed
        case .alwaysDeny: return .denied
        default: return .ask
        }
    }
}
