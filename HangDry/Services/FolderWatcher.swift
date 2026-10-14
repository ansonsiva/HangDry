import Foundation
import Observation
import os

/// 自动挂绳目录：目录里出现新文件、且写入完成后，自动挂到绳上。
@MainActor
@Observable
final class FolderWatcher {
    struct Folder: Identifiable, Codable, Sendable {
        let id: UUID
        var bookmark: Data
        var path: String

        var name: String { (path as NSString).lastPathComponent }
    }

    private(set) var folders: [Folder] = []

    @ObservationIgnored var onNewFiles: (([URL]) -> Void)?
    @ObservationIgnored private var monitors: [UUID: DirectoryMonitor] = [:]
    @ObservationIgnored private let defaultsKey = "watchedFolders"
    @ObservationIgnored private let logger = Logger(subsystem: "com.huck.HangDry", category: "watcher")

    func start() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([Folder].self, from: data) {
            folders = saved
        }
        for folder in folders {
            begin(folder, url: nil, includeExisting: false)
        }
    }

    func add(_ url: URL, includeExisting: Bool) {
        let url = url.standardizedFileURL
        guard !folders.contains(where: { $0.path == url.path }) else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let folder = Folder(id: UUID(), bookmark: bookmark, path: url.path)
            folders.append(folder)
            save()
            begin(folder, url: url, includeExisting: includeExisting)
        } catch {
            logger.error("无法监听 \(url.path, privacy: .public)：\(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(_ id: UUID) {
        monitors.removeValue(forKey: id)?.stop()
        folders.removeAll { $0.id == id }
        save()
    }

    func url(for folder: Folder) -> URL? { monitors[folder.id]?.url }

    private func begin(_ folder: Folder, url: URL?, includeExisting: Bool) {
        var resolved = url
        var isScoped = false
        if resolved == nil {
            var isStale = false
            resolved = try? URL(resolvingBookmarkData: folder.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
            isScoped = resolved?.startAccessingSecurityScopedResource() ?? false
        }
        guard let resolved else {
            logger.error("监听目录已失效：\(folder.path, privacy: .public)")
            return
        }
        let monitor = DirectoryMonitor(url: resolved, isScoped: isScoped) { [weak self] urls in
            self?.onNewFiles?(urls)
        }
        monitor.start(includeExisting: includeExisting)
        monitors[folder.id] = monitor
    }

    private func save() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

/// 监听单个目录的第一层。文件大小和修改时间连续两次一致才算写完，避免挂上下载或渲染到一半的文件。
@MainActor
private final class DirectoryMonitor {
    let url: URL
    private let isScoped: Bool
    private let onReady: ([URL]) -> Void
    private var source: DispatchSourceFileSystemObject?
    /// 已处理过的路径（启动时已存在的，或已挂上的）。
    private var known: Set<String> = []
    /// 等待写入完成的路径 → 上次检查时的签名。
    private var pending: [String: String] = [:]
    private var isCheckScheduled = false

    private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    init(url: URL, isScoped: Bool, onReady: @escaping ([URL]) -> Void) {
        self.url = url
        self.isScoped = isScoped
        self.onReady = onReady
    }

    func start(includeExisting: Bool) {
        if !includeExisting {
            known = Set(listing().map(\.path))
        }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        if includeExisting { scan() }
    }

    func stop() {
        source?.cancel()
        source = nil
        if isScoped { url.stopAccessingSecurityScopedResource() }
    }

    private func listing() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    private func scan() {
        let entries = listing()
        known.formIntersection(entries.map(\.path))
        for entry in entries where !known.contains(entry.path) && pending[entry.path] == nil {
            guard !Self.partialExtensions.contains(entry.pathExtension.lowercased()),
                  let signature = signature(of: entry)
            else { continue }
            pending[entry.path] = signature
        }
        scheduleCheck()
    }

    private func scheduleCheck() {
        guard !pending.isEmpty, !isCheckScheduled else { return }
        isCheckScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.checkPending()
        }
    }

    private func checkPending() {
        isCheckScheduled = false
        var ready: [URL] = []
        for (path, previous) in pending {
            let entry = URL(filePath: path)
            guard let current = signature(of: entry) else {
                pending[path] = nil
                continue
            }
            if current == previous {
                pending[path] = nil
                known.insert(path)
                ready.append(entry)
            } else {
                pending[path] = current
            }
        }
        if !ready.isEmpty {
            onReady(ready.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        }
        scheduleCheck()
    }

    /// 普通文件大小为 0 时返回 "empty"，表示还没开始写，不会被当作稳定。
    private func signature(of entry: URL) -> String? {
        guard let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else { return nil }
        let size = values.fileSize ?? 0
        if values.isDirectory != true && size == 0 { return "empty-\(UUID().uuidString)" }
        return "\(size)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }
}
