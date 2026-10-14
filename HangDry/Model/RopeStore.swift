import AppKit
import Observation
import os

/// 绳上所有衣服的数据源：负责书签解析、沙盒访问权限、持久化。
@MainActor
@Observable
final class RopeStore {
    private(set) var items: [HungItem] = []
    private(set) var missing: Set<UUID> = []

    @ObservationIgnored private var urls: [UUID: URL] = [:]
    /// 通过安全作用域书签打开的 URL，取下时需要 stopAccessing。
    @ObservationIgnored private var scoped: Set<UUID> = []
    @ObservationIgnored private let fileManager = FileManager.default
    @ObservationIgnored private let logger = Logger(subsystem: "com.huck.HangDry", category: "store")

    nonisolated static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "HangDry", directoryHint: .isDirectory)
    }()

    /// 存放 rope.json 和副本的目录（沙盒里位于 App 容器内）。
    @ObservationIgnored let directory: URL

    private var copiesDirectory: URL { directory.appending(path: "Copies", directoryHint: .isDirectory) }
    private var storeURL: URL { directory.appending(path: "rope.json") }

    init(directory: URL = RopeStore.defaultDirectory) {
        self.directory = directory
        load()
    }

    func url(for id: UUID) -> URL? { urls[id] }

    func item(for id: UUID) -> HungItem? { items.first { $0.id == id } }

    // MARK: - 挂上去

    /// 挂上文件。`index` 指定插在第几件之前，nil 表示挂在最后。已经在绳上的文件会跳过。
    @discardableResult
    func hang(_ incoming: [URL], origin: HungItem.Origin, isCopy: Bool = false, at index: Int? = nil) -> [UUID] {
        var seen = Set(urls.values.map(\.standardizedFileURL.path))
        var newItems: [HungItem] = []
        for raw in incoming where raw.isFileURL {
            let url = raw.standardizedFileURL
            guard !seen.contains(url.path) else { continue }
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                let item = HungItem(
                    id: UUID(), bookmark: bookmark, name: url.lastPathComponent, path: url.path,
                    kind: FileKind.classify(url), origin: origin, isCopy: isCopy, addedAt: .now
                )
                newItems.append(item)
                urls[item.id] = url
                seen.insert(url.path)
            } catch {
                logger.error("无法为 \(url.path, privacy: .public) 创建书签：\(error.localizedDescription, privacy: .public)")
            }
        }
        guard !newItems.isEmpty else { return [] }
        let position = min(max(index ?? items.count, 0), items.count)
        items.insert(contentsOf: newItems, at: position)
        save()
        return newItems.map(\.id)
    }

    /// 先把文件复制到 App 自己的目录，再把副本挂上去。
    @discardableResult
    func hangCopies(of sources: [URL], at index: Int? = nil) async -> [UUID] {
        hang(await makeCopies(of: sources), origin: .dropped, isCopy: true, at: index)
    }

    /// 在后台把文件复制到 App 自己的目录，返回副本位置。
    func makeCopies(of sources: [URL]) async -> [URL] {
        let copiesDirectory = copiesDirectory
        return await Task.detached(priority: .userInitiated) {
            sources.compactMap { RopeStore.makeCopy(of: $0, in: copiesDirectory) }
        }.value
    }

    /// 新建一个放副本的空文件夹（每个副本单独一个，避免重名）。
    func makeCopyFolder() -> URL? {
        let folder = copiesDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            logger.error("创建副本目录失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 没有对应文件的图片（浏览器里拷贝的图、截图）存成副本再挂上。
    @discardableResult
    func hangImage(_ clip: ImageClip, named fileName: String, origin: HungItem.Origin, at index: Int? = nil) -> UUID? {
        let folder = copiesDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let target = folder.appending(path: fileName)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try clip.data.write(to: target, options: .atomic)
        } catch {
            logger.error("保存图片失败：\(error.localizedDescription, privacy: .public)")
            try? fileManager.removeItem(at: folder)
            return nil
        }
        return hang([target], origin: origin, isCopy: true, at: index).first
    }

    nonisolated private static func makeCopy(of source: URL, in copiesDirectory: URL) -> URL? {
        let folder = copiesDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let target = folder.appending(path: source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    // MARK: - 取下 / 删除

    /// 只把链接从绳上取下，原文件不动；副本会一并删除。
    func takeDown(_ ids: Set<UUID>) {
        discard(detach(ids))
    }

    /// 从绳上摘下来但先不清理：访问权限和副本文件都留着，`restore` 可以原样放回，`discard` 才真正清理。
    struct Detached {
        struct Entry {
            let index: Int
            let item: HungItem
            let url: URL?
            let isScoped: Bool
            let wasMissing: Bool
        }

        let id = UUID()
        let entries: [Entry]

        var count: Int { entries.count }
        var copyCount: Int { entries.filter(\.item.isCopy).count }
    }

    func detach(_ ids: Set<UUID>) -> Detached {
        let entries = items.enumerated().compactMap { index, item -> Detached.Entry? in
            guard ids.contains(item.id) else { return nil }
            return Detached.Entry(
                index: index, item: item, url: urls[item.id],
                isScoped: scoped.contains(item.id), wasMissing: missing.contains(item.id)
            )
        }
        for entry in entries {
            urls[entry.item.id] = nil
            scoped.remove(entry.item.id)
            missing.remove(entry.item.id)
        }
        items.removeAll { ids.contains($0.id) }
        save()
        return Detached(entries: entries)
    }

    /// 撤销取下：按原来的位置放回。
    func restore(_ detached: Detached) {
        for entry in detached.entries.sorted(by: { $0.index < $1.index }) {
            items.insert(entry.item, at: min(entry.index, items.count))
            urls[entry.item.id] = entry.url
            if entry.isScoped { scoped.insert(entry.item.id) }
            if entry.wasMissing { missing.insert(entry.item.id) }
        }
        save()
    }

    /// 确认取下：结束访问权限，删除副本文件。
    func discard(_ detached: Detached) {
        ThumbnailCache.shared.forget(detached.entries.map(\.item.id))
        for entry in detached.entries {
            guard let url = entry.url else { continue }
            if entry.item.isCopy {
                try? fileManager.removeItem(at: url)
                removeEmptyCopyFolder(containing: url)
            }
            if entry.isScoped { url.stopAccessingSecurityScopedResource() }
        }
    }

    /// 删除真实文件：移到废纸篓，可以从废纸篓找回。返回删除失败的文件名。
    func trash(_ ids: Set<UUID>) -> [String] {
        var failures: [String] = []
        var removed: Set<UUID> = []
        for item in items where ids.contains(item.id) {
            guard let url = urls[item.id], !missing.contains(item.id) else {
                removed.insert(item.id)
                continue
            }
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                if item.isCopy { removeEmptyCopyFolder(containing: url) }
                removed.insert(item.id)
            } catch {
                failures.append(item.name)
            }
        }
        for id in removed { release(id) }
        items.removeAll { removed.contains($0.id) }
        save()
        return failures
    }

    // MARK: - 调整位置

    /// 把这些衣服（保持原来的先后）挪到第 `index` 件之前；`index` 按挪动前的位置算。
    func move(_ ids: Set<UUID>, to index: Int) {
        let moving = items.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return }
        let clamped = min(max(index, 0), items.count)
        let movedBefore = items[..<clamped].filter { ids.contains($0.id) }.count
        var rest = items.filter { !ids.contains($0.id) }
        rest.insert(contentsOf: moving, at: min(clamped - movedBefore, rest.count))
        guard rest.map(\.id) != items.map(\.id) else { return }
        items = rest
        save()
    }

    // MARK: - 备注名

    /// 设置备注名；空字符串或和原文件名相同时清除。
    func setLabel(_ label: String?, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newLabel = trimmed.isEmpty || trimmed == items[index].name ? nil : trimmed
        guard items[index].label != newLabel else { return }
        items[index].label = newLabel
        save()
    }

    // MARK: - 排序

    enum SortOrder: String, CaseIterable, Identifiable {
        case kind, created, modified, name

        var id: Self { self }

        var title: String {
            switch self {
            case .kind: String(localized: "按类型")
            case .created: String(localized: "按创建时间")
            case .modified: String(localized: "按修改时间")
            case .name: String(localized: "按名称")
            }
        }

        var doneMessage: String {
            switch self {
            case .kind: String(localized: "已按类型排好")
            case .created: String(localized: "已按创建时间排好")
            case .modified: String(localized: "已按修改时间排好")
            case .name: String(localized: "已按名称排好")
            }
        }
    }

    /// 一次性把绳上的衣服重新排好：类型按 视频→音频→图片→文档→工程… 的顺序，时间新的在前。找不到的文件排最后。
    func sort(by order: SortOrder) {
        let keys = [URLResourceKey.creationDateKey, .contentModificationDateKey]
        func date(_ item: HungItem) -> Date? {
            guard let url = urls[item.id], !missing.contains(item.id),
                  let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return order == .created ? values.creationDate : values.contentModificationDate
        }
        func byName(_ a: HungItem, _ b: HungItem) -> Bool {
            a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
        let kindRank = Dictionary(uniqueKeysWithValues: FileKind.allCases.enumerated().map { ($1, $0) })
        let dates = Dictionary(uniqueKeysWithValues: items.map { ($0.id, date($0)) })

        let present = items.filter { !missing.contains($0.id) }
        let absent = items.filter { missing.contains($0.id) }
        let sorted: [HungItem] = switch order {
        case .kind:
            present.sorted { kindRank[$0.kind]! != kindRank[$1.kind]! ? kindRank[$0.kind]! < kindRank[$1.kind]! : byName($0, $1) }
        case .created, .modified:
            present.sorted {
                switch (dates[$0.id] ?? nil, dates[$1.id] ?? nil) {
                case let (a?, b?) where a != b: a > b
                case (_?, nil): true
                case (nil, _?): false
                default: byName($0, $1)
                }
            }
        case .name:
            present.sorted(by: byName)
        }
        let result = sorted + absent
        guard result.map(\.id) != items.map(\.id) else { return }
        items = result
        save()
    }

    // MARK: - 收衣服

    func collectJobs() -> [Collector.Job] {
        items.compactMap { item in
            guard !missing.contains(item.id), let url = urls[item.id] else { return nil }
            return Collector.Job(id: item.id, source: url, kind: item.kind, name: item.name, label: item.label)
        }
    }

    func finishCollect(_ report: Collector.Report) {
        let collected = Set(report.moved.map(\.id))
        for item in items where collected.contains(item.id) {
            if item.isCopy, let url = urls[item.id] { removeEmptyCopyFolder(containing: url) }
            release(item.id)
        }
        items.removeAll { collected.contains($0.id) }
        save()
    }

    // MARK: - 跟随改名和移动

    /// 原位置找不到文件时重新解析书签，跟上改名、移动后的新位置。
    func refreshMovedItems() {
        var changed = false
        for index in items.indices {
            let id = items[index].id
            if let url = urls[id], fileManager.fileExists(atPath: url.path) {
                if missing.contains(id) { missing.remove(id) }
                continue
            }
            release(id)
            if let url = resolve(&items[index]) {
                urls[id] = url
                if missing.contains(id) { missing.remove(id) }
                changed = true
            } else if !missing.contains(id) {
                missing.insert(id)
            }
        }
        if changed { save() }
    }

    // MARK: - 私有

    private func resolve(_ item: inout HungItem) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: item.bookmark, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &isStale
        ) else { return nil }

        let didStart = url.startAccessingSecurityScopedResource()
        guard fileManager.fileExists(atPath: url.path), !url.path.contains("/.Trash/") else {
            if didStart { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        if didStart { scoped.insert(item.id) }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            item.bookmark = fresh
        }
        item.path = url.path
        item.name = url.lastPathComponent
        return url
    }

    private func release(_ id: UUID) {
        ThumbnailCache.shared.forget([id])
        if scoped.remove(id) != nil { urls[id]?.stopAccessingSecurityScopedResource() }
        urls[id] = nil
    }

    private func removeEmptyCopyFolder(containing url: URL) {
        let folder = url.deletingLastPathComponent()
        guard folder.deletingLastPathComponent().standardizedFileURL.path == copiesDirectory.standardizedFileURL.path,
              (try? fileManager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true
        else { return }
        try? fileManager.removeItem(at: folder)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              var decoded = try? JSONDecoder().decode([HungItem].self, from: data)
        else { return }
        for index in decoded.indices {
            if let url = resolve(&decoded[index]) {
                urls[decoded[index].id] = url
            } else {
                missing.insert(decoded[index].id)
            }
        }
        items = decoded
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: storeURL, options: .atomic)
        } catch {
            logger.error("保存晾衣绳失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
