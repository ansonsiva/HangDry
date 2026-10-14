import CoreGraphics

enum RopeMetrics {
    /// 绳子两端在面板里的高度
    static let anchorY: CGFloat = 4
    static let collapsedHeight: CGFloat = 10
    static let expandedHeight: CGFloat = 160
    static let cardWidth: CGFloat = 76
    static let cardSpacing: CGFloat = 12
    /// 衣服太多时最小间距，卡片会互相叠住
    static let minSlot: CGFloat = 26
    static let pinWidth: CGFloat = 9
    static let pinHeight: CGFloat = 24
    /// 衣夹顶端高出绳子的距离（绳子从衣夹上部穿过）
    static let pinAboveRope: CGFloat = 6
    /// 卡片顶边盖住衣夹下部的高度
    static let pinCardOverlap: CGFloat = 9
    static let baseSag: CGFloat = 14
    static let maxSag: CGFloat = 30
    /// 拖着文件经过时，绳子在预备挂的位置额外往下坠的深度
    static let pullSag: CGFloat = 10
    /// 左右两侧留给收衣服按钮的宽度
    static let sideReserve: CGFloat = 170
    /// 展开时绳子附近可以接收拖放的高度
    static let ropeBand: CGFloat = 34
    /// 绳子画布的高度：够画最深的下垂、起伏和投影就行，画布越小每帧越省
    static let ropeCanvasHeight: CGFloat = 64
    /// 拖着文件进入菜单栏下方这么深的范围就铺开晾衣台。
    /// 不要求顶到屏幕边缘：拖拽时光标在顶边停留会触发系统的调度中心。
    static let dragTriggerDepth: CGFloat = 44
    /// 拖着文件离菜单栏这么近时，绳子垂下一个“拖到这里”的小标签当目标
    static let dragHintDistance: CGFloat = 240
}

/// 绳子形状和每件衣服的位置。
/// 绳子是二次贝塞尔曲线；拖文件经过时控制点移到预备挂的位置，绳子被“拽”下去，并在那里空出一个槽位。
struct RopeLayout {
    let width: CGFloat
    let count: Int
    let sag: CGFloat
    let slot: CGFloat
    let startX: CGFloat
    /// 预留给新衣服的位置（插入下标），nil 表示没有在拖
    let gapIndex: Int?
    /// 贝塞尔控制点的 x
    let controlX: CGFloat

    init(width: CGFloat, count: Int, expanded: Bool, gapIndex: Int? = nil) {
        self.width = width
        self.count = count
        let gapIndex = gapIndex.map { min(max($0, 0), count) }
        self.gapIndex = gapIndex

        if expanded {
            sag = min(RopeMetrics.baseSag + CGFloat(count) * 1.5, RopeMetrics.maxSag) + (gapIndex == nil ? 0 : RopeMetrics.pullSag)
        } else {
            sag = 0
        }

        let slots = count + (gapIndex == nil ? 0 : 1)
        let ideal = RopeMetrics.cardWidth + RopeMetrics.cardSpacing
        let available = max(width - RopeMetrics.sideReserve * 2 - RopeMetrics.cardWidth, 0)
        if slots > 1 {
            slot = min(ideal, max(available / CGFloat(slots - 1), RopeMetrics.minSlot))
        } else {
            slot = ideal
        }
        let startX = width / 2 - CGFloat(max(slots - 1, 0)) * slot / 2
        self.startX = startX

        if let gapIndex, width > 0 {
            let gapX = startX + CGFloat(gapIndex) * slot
            controlX = min(max(gapX, width * 0.2), width * 0.8)
        } else {
            controlX = width / 2
        }
    }

    func x(_ index: Int) -> CGFloat {
        let position = if let gapIndex, index >= gapIndex { index + 1 } else { index }
        return startX + CGFloat(position) * slot
    }

    /// 新衣服的预备位置
    var gapX: CGFloat? {
        gapIndex.map { startX + CGFloat($0) * slot }
    }

    /// 光标在 x 处松手时，新衣服应该插在第几件之前。
    func insertionIndex(at x: CGFloat) -> Int {
        let plain = RopeLayout(width: width, count: count, expanded: true)
        return (0..<count).filter { plain.x($0) < x }.count
    }

    func ropeY(at x: CGFloat) -> CGFloat {
        Self.curveY(at: x, width: width, sag: sag, controlX: controlX)
    }

    /// 曲线 P0=(0,a) C=(cx,a+2s) P2=(W,a)：先由 x 反解参数 t，再求 y = a + 4s·t(1-t)
    static func curveY(at x: CGFloat, width: CGFloat, sag: CGFloat, controlX: CGFloat) -> CGFloat {
        guard width > 0 else { return RopeMetrics.anchorY }
        let x = min(max(x, 0), width)
        let a = width - 2 * controlX
        let t: CGFloat
        if abs(a) < 0.001 {
            t = x / width
        } else {
            t = (-controlX + (controlX * controlX + a * x).squareRoot()) / a
        }
        let clamped = min(max(t, 0), 1)
        return RopeMetrics.anchorY + 4 * sag * clamped * (1 - clamped)
    }

    /// 衣服占据的横向范围（含少量余量），用来判断鼠标是否还在晾衣绳上。
    var clothesRange: ClosedRange<CGFloat>? {
        guard count > 0 else { return nil }
        let margin = RopeMetrics.cardWidth / 2 + 24
        return (x(0) - margin)...(x(count - 1) + margin)
    }
}
