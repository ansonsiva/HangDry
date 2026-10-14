import AppKit
import UniformTypeIdentifiers

/// 拖进来的内容。
enum DropPayload {
    /// 普通文件（Finder 等）
    case files([URL])
    /// 文件承诺：浏览器、照片等 App 拖出来的图片，松手后由对方写出文件
    case promises([NSFilePromiseReceiver])
    /// 只有图片数据
    case image(ImageClip, sourceURL: URL?)
}

/// 从拖拽剪贴板读取内容。
@MainActor
enum DropLoader {
    static let draggedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL]
        + ImageClip.preferredTypes.map { NSPasteboard.PasteboardType($0.identifier) }
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    /// 依次尝试：文件链接 → 文件承诺 → 图片数据。
    static func read(_ pasteboard: NSPasteboard) -> DropPayload? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            return .promises(receivers)
        }
        if let (clip, source) = ImageClip.read(from: pasteboard) {
            return .image(clip, sourceURL: source)
        }
        return nil
    }

    /// 开始接收文件承诺：让对方把文件写到各自的文件夹里，返回一个可以异步等待结果的 `PromisedFiles`。
    ///
    /// 必须在松手的那一刻（`performDragOperation` 里）同步调用：系统只允许在拖放回调期间发起接收，
    /// 事后再调会直接抛异常。
    static func startReceiving(_ receivers: [NSFilePromiseReceiver], makeFolder: () -> URL?) -> PromisedFiles {
        let promised = PromisedFiles(expected: receivers.reduce(0) { $0 + max($1.fileTypes.count, 1) })
        for receiver in receivers {
            guard let folder = makeFolder() else {
                promised.skip(max(receiver.fileTypes.count, 1))
                continue
            }
            receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: promiseQueue,
                                          reader: makeReader(for: promised))
        }
        return promised
    }

    /// 对方写好文件后在 `promiseQueue` 上回调。回调必须是 @Sendable（不属于主线程）：
    /// 如果被推断成只能在主线程跑，Swift 6 的运行时检查会在后台队列上直接让 App 停下（_dispatch_assert_queue_fail）。
    nonisolated static func makeReader(for promised: PromisedFiles) -> @Sendable (URL, (any Error)?) -> Void {
        { url, error in promised.add(error == nil ? url : nil) }
    }

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()
}

/// 正在接收的文件承诺。后台队列逐个回报，全部到齐或超时（默认 30 秒）后，`value()` 返回已写好的文件。
final class PromisedFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var urls: [URL] = []
    private var isFinished = false
    private var continuation: CheckedContinuation<[URL], Never>?

    init(expected: Int, timeout: TimeInterval = 30) {
        remaining = expected
        if expected <= 0 {
            isFinished = true
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in finish() }
        }
    }

    func add(_ url: URL?) {
        let isDone = lock.withLock {
            if let url { urls.append(url) }
            remaining -= 1
            return remaining <= 0
        }
        if isDone { finish() }
    }

    func skip(_ count: Int) {
        let isDone = lock.withLock {
            remaining -= count
            return remaining <= 0
        }
        if isDone { finish() }
    }

    func value() async -> [URL] {
        await withCheckedContinuation { continuation in
            let ready: [URL]? = lock.withLock {
                if isFinished { return urls }
                self.continuation = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }

    private func finish() {
        let (continuation, result): (CheckedContinuation<[URL], Never>?, [URL]) = lock.withLock {
            guard !isFinished else { return (nil, []) }
            isFinished = true
            let pending = self.continuation
            self.continuation = nil
            return (pending, urls)
        }
        continuation?.resume(returning: result)
    }
}
