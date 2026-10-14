import Foundation

/// 挂在绳上的一件“衣服”。默认只保存指向原文件的书签；`isCopy` 为真时文件是挂绳时复制出来的副本。
struct HungItem: Identifiable, Codable, Sendable, Equatable {
    enum Origin: String, Codable, Sendable {
        case dropped, pasted, watched
    }

    let id: UUID
    var bookmark: Data
    var name: String
    var path: String
    var kind: FileKind
    var origin: Origin
    var isCopy: Bool
    var addedAt: Date
    /// 备注名：只在绳上显示（收衣服时可选用来命名），原文件名不动
    var label: String?

    var displayName: String { label ?? name }
}
