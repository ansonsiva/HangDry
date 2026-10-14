import Foundation

/// 收衣服：把绳上的文件按类型移动到归档目录的子文件夹里，并留下一份移动清单。
enum Collector {
    struct Job: Sendable {
        let id: UUID
        let source: URL
        let kind: FileKind
        let name: String
        var label: String?

        /// 归档后的文件名：用备注名时保留原扩展名
        func targetName(usingLabel: Bool) -> String {
            guard usingLabel, let label else { return source.lastPathComponent }
            let safe = label.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let ext = source.pathExtension
            guard !ext.isEmpty, !safe.lowercased().hasSuffix("." + ext.lowercased()) else { return safe }
            return safe + "." + ext
        }
    }

    struct Report: Sendable {
        struct Moved: Codable, Sendable {
            let id: UUID
            let from: String
            let to: String
        }

        struct Failed: Sendable {
            let id: UUID
            let name: String
            let reason: String
        }

        let destination: URL
        var moved: [Moved] = []
        var failed: [Failed] = []
        var manifestURL: URL?
    }

    private struct Manifest: Encodable {
        let collectedAt: Date
        let destination: String
        let files: [Report.Moved]
    }

    static func run(_ jobs: [Job], into destination: URL, usingLabels: Bool = false,
                    progress: @Sendable (Int) -> Void) -> Report {
        let fileManager = FileManager()
        var report = Report(destination: destination)

        for (index, job) in jobs.enumerated() {
            defer { progress(index + 1) }
            let folder = destination.appending(path: job.kind.folderName, directoryHint: .isDirectory)
            let source = job.source.standardizedFileURL

            let targetName = job.targetName(usingLabel: usingLabels)
            // 已经在目标分类文件夹里、也不用改名的文件原地保留
            if source.deletingLastPathComponent().path == folder.standardizedFileURL.path,
               targetName == source.lastPathComponent {
                report.moved.append(.init(id: job.id, from: source.path, to: source.path))
                continue
            }

            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = availableURL(for: targetName, in: folder, fileManager: fileManager)
                try fileManager.moveItem(at: source, to: target)
                report.moved.append(.init(id: job.id, from: source.path, to: target.path))
            } catch {
                report.failed.append(.init(id: job.id, name: job.name, reason: error.localizedDescription))
            }
        }

        if !report.moved.isEmpty {
            report.manifestURL = writeManifest(for: report)
        }
        return report
    }

    /// 重名时追加序号：clip.mov → clip 2.mov
    static func availableURL(for fileName: String, in folder: URL, fileManager: FileManager) -> URL {
        var candidate = folder.appending(path: fileName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var number = 2
        repeat {
            candidate = folder.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func writeManifest(for report: Report) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = report.destination.appending(path: String(localized: "收衣服记录 \(formatter.string(from: .now)).json"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let manifest = Manifest(collectedAt: .now, destination: report.destination.path, files: report.moved)
        do {
            try encoder.encode(manifest).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
