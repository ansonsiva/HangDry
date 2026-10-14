import AppKit
import Testing

/// 浏览器、微信、照片拖出来的图片是“文件承诺”：松手时发起接收，对方写好文件后在后台队列上回调。
/// （发起接收本身只能在真实拖放的回调里调用，测试里只能测回调和等待这两段。）
struct FilePromiseTests {
    /// 回调在后台队列上执行。它要是被推断成只能在主线程跑，这里会触发 _dispatch_assert_queue_fail 让测试进程直接停下。
    @Test func readerRunsOnBackgroundQueue() async {
        let promised = PromisedFiles(expected: 2)
        let reader = DropLoader.makeReader(for: promised)
        let a = URL(filePath: "/tmp/网页里的图.png")
        let b = URL(filePath: "/tmp/另一张.jpg")

        DispatchQueue.global().async {
            reader(a, nil)
            reader(b, nil)
        }

        #expect(await promised.value() == [a, b])
    }

    @Test func failedFilesAreSkipped() async {
        let promised = PromisedFiles(expected: 2)
        let reader = DropLoader.makeReader(for: promised)
        let a = URL(filePath: "/tmp/a.png")

        DispatchQueue.global().async {
            reader(a, nil)
            reader(URL(filePath: "/tmp/failed.png"), CocoaError(.fileWriteUnknown))
        }

        #expect(await promised.value() == [a])
    }

    @Test func waitingAfterCompletionReturnsImmediately() async {
        let promised = PromisedFiles(expected: 1)
        let a = URL(filePath: "/tmp/a.png")
        promised.add(a)
        #expect(await promised.value() == [a])
    }

    @Test func givesUpAfterTimeout() async {
        let promised = PromisedFiles(expected: 3, timeout: 0.2)
        let a = URL(filePath: "/tmp/a.png")
        promised.add(a)
        // 另外两件一直没写好，超时后返回已经到的
        #expect(await promised.value() == [a])
    }

    @Test func skippedReceiversCountTowardsCompletion() async {
        let promised = PromisedFiles(expected: 2)
        promised.skip(1)
        promised.add(URL(filePath: "/tmp/a.png"))
        #expect(await promised.value().count == 1)
    }
}
