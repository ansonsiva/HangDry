import CoreGraphics
import Foundation
import Observation

/// 晾衣绳的物理：绳子的下垂和被拽、挂上东西时的起伏、每件衣服的滑动、落下回弹和摆动。
///
/// 布局（RopeLayout）给出“应该在哪”，这里用弹簧和单摆算出“此刻在哪”。
/// 只在有东西在动时逐帧计算；全部静止后暂停 TimelineView，不占 CPU。
@MainActor
@Observable
final class RopeSimulation {
    struct Targets: Equatable {
        struct Clothes: Equatable {
            let id: UUID
            let x: CGFloat
        }

        var width: CGFloat
        var sag: CGFloat
        var controlX: CGFloat
        var isExpanded: Bool
        var clothes: [Clothes]
        var ghostX: CGFloat?
        /// 拖拽提示、虚线衣服这类需要一直动的状态
        var isContinuous: Bool
    }

    /// 一件衣服此刻的位置：x 是衣夹中心，y 是绳子穿过衣夹的高度，angle 是摆动角度（弧度）。
    struct Pose {
        let x: CGFloat
        let y: CGFloat
        let angle: CGFloat
    }

    static let ghostID = UUID()

    /// TimelineView 是否在逐帧刷新
    private(set) var isRunning = false

    @ObservationIgnored private var width: CGFloat = 0
    @ObservationIgnored private var sag = Spring(stiffness: 170, damping: 13)
    @ObservationIgnored private var controlX = Spring(stiffness: 120, damping: 18)
    /// 0 收起，1 展开；决定绳子粗细
    @ObservationIgnored private var openness = Spring(stiffness: 200, damping: 24)
    @ObservationIgnored private var nodes: [UUID: Node] = [:]
    @ObservationIgnored private var ripples: [Ripple] = []
    @ObservationIgnored private var lastTime: TimeInterval?
    @ObservationIgnored private var previous: Targets?
    @ObservationIgnored private var isPauseScheduled = false
    @ObservationIgnored private var lastNudge: [UUID: TimeInterval] = [:]

    // MARK: - 每帧

    /// 推进到 `now`。在 TimelineView 的内容里调用（只改不被观察的状态）。
    func advance(to now: TimeInterval, targets: Targets) {
        apply(targets)
        guard let lastTime else {
            self.lastTime = now
            return
        }
        let dt = min(max(now - lastTime, 0), 1.0 / 30)
        self.lastTime = now
        guard dt > 0 else { return }
        let substeps = 2
        for _ in 0..<substeps { integrate(CGFloat(dt) / CGFloat(substeps)) }

        if isRunning, !targets.isContinuous, isSettled, !isPauseScheduled {
            isPauseScheduled = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                isPauseScheduled = false
                if isSettled, previous?.isContinuous != true {
                    isRunning = false
                    self.lastTime = nil
                }
            }
        }
    }

    /// 直接摆到目标位置，不做动画（离屏渲染用）。
    func snap(to targets: Targets) {
        previous = nil
        nodes = [:]
        ripples = []
        apply(targets)
        sag.snap()
        controlX.snap()
        openness.snap()
        for id in nodes.keys { nodes[id]?.snap() }
    }

    func wake() {
        guard !isRunning else { return }
        lastTime = nil
        isRunning = true
    }

    /// 鼠标经过时轻轻碰一下。同一件衣服 0.8 秒内只碰一次，摆着的时候不再加力。
    func nudge(_ id: UUID) {
        guard let node = nodes[id] else { return }
        let now = Date.now.timeIntervalSinceReferenceDate
        if let last = lastNudge[id], now - last < 0.8 { return }
        guard abs(node.angularVelocity) < 0.4 else { return }
        lastNudge[id] = now
        nodes[id]?.angularVelocity += (Bool.random() ? 1 : -1) * 0.7
        wake()
    }

    // MARK: - 读取

    /// 小于肉眼可见的残余摆动、偏移直接归零，并把位置取整到半个点：
    /// 静止的衣服每帧给出完全相同的值，SwiftUI 就不会重画它。
    func pose(for id: UUID) -> Pose? {
        guard let node = nodes[id] else { return nil }
        let angle = abs(node.angle) < 0.004 ? 0 : node.angle
        let x = (node.x.value * 2).rounded() / 2
        let y = ((ropeY(at: node.x.value) + node.drop.value) * 2).rounded() / 2
        return Pose(x: x, y: y, angle: angle)
    }

    var ghostPose: Pose? { pose(for: Self.ghostID) }

    /// 0 收起，1 展开
    var expansion: CGFloat { min(max(openness.value, 0), 1) }

    func ropeY(at x: CGFloat) -> CGFloat {
        var y = RopeLayout.curveY(at: x, width: width, sag: sag.value, controlX: controlX.value)
        guard width > 0, !ripples.isEmpty else { return y }
        let pinned = sin(.pi * min(max(x / width, 0), 1))
        for ripple in ripples {
            let local = exp(-pow((x - ripple.x) / Ripple.spread, 2))
            y += ripple.displacement * pinned * (0.35 + 0.65 * local)
        }
        return y
    }

    /// 绳子当前形状的采样点
    func ropePoints(step: CGFloat = 8) -> [CGPoint] {
        guard width > 0 else { return [] }
        var points: [CGPoint] = []
        var x: CGFloat = 0
        while x < width {
            points.append(CGPoint(x: x, y: ropeY(at: x)))
            x += step
        }
        points.append(CGPoint(x: width, y: ropeY(at: width)))
        return points
    }

    // MARK: - 私有

    private func apply(_ targets: Targets) {
        let isFirst = previous == nil || width != targets.width
        width = targets.width
        sag.target = targets.sag
        controlX.target = targets.controlX
        openness.target = targets.isExpanded ? 1 : 0
        if isFirst {
            sag.snap()
            controlX.snap()
            openness.snap()
        }

        var vanishedGhost = targets.ghostX == nil ? nodes[Self.ghostID] : nil
        var alive: Set<UUID> = []

        for clothes in targets.clothes {
            alive.insert(clothes.id)
            if nodes[clothes.id] != nil {
                nodes[clothes.id]?.x.target = clothes.x
            } else if isFirst {
                nodes[clothes.id] = Node(x: clothes.x, drop: 0)
            } else if var ghost = vanishedGhost {
                // 松手：虚线衣服就地变成真衣服，衣夹“咔”地夹紧
                ghost.x.target = clothes.x
                ghost.drop.value = -6
                ghost.angularVelocity += 0.8
                nodes[clothes.id] = ghost
                vanishedGhost = nil
                ripples.append(Ripple(x: clothes.x, amplitude: 6))
            } else {
                // 新衣服从上方落到绳上
                var node = Node(x: clothes.x, drop: -28)
                node.angularVelocity = (Bool.random() ? 1 : -1) * CGFloat.random(in: 1.6...2.4)
                nodes[clothes.id] = node
                ripples.append(Ripple(x: clothes.x, amplitude: 5))
            }
        }

        if let ghostX = targets.ghostX {
            alive.insert(Self.ghostID)
            if nodes[Self.ghostID] != nil {
                nodes[Self.ghostID]?.x.target = ghostX
            } else {
                var node = Node(x: ghostX, drop: -18)
                node.angularVelocity = 1.4
                nodes[Self.ghostID] = node
                ripples.append(Ripple(x: ghostX, amplitude: 3))
            }
        }

        for (id, node) in nodes where !alive.contains(id) {
            // 衣服被取走，绳子轻轻弹起
            if id != Self.ghostID { ripples.append(Ripple(x: node.x.value, amplitude: -3)) }
            nodes[id] = nil
            lastNudge[id] = nil
        }

        // 展开时所有衣服跟着绳子落下，左右错开地晃起来
        if let previous, !previous.isExpanded, targets.isExpanded {
            for (offset, id) in nodes.keys.sorted(by: { nodes[$0]!.x.value < nodes[$1]!.x.value }).enumerated() {
                nodes[id]?.angularVelocity += (offset.isMultiple(of: 2) ? 1 : -1) * 1.1
            }
        }
        if ripples.count > 12 { ripples.removeFirst(ripples.count - 12) }
        previous = targets
    }

    private func integrate(_ dt: CGFloat) {
        sag.step(dt)
        controlX.step(dt)
        openness.step(dt)
        for id in nodes.keys {
            nodes[id]?.step(dt)
        }
        for index in ripples.indices {
            ripples[index].age += dt
        }
        ripples.removeAll { $0.age > Ripple.lifetime }
    }

    private var isSettled: Bool {
        sag.isSettled && controlX.isSettled && openness.isSettled
            && ripples.isEmpty
            && nodes.values.allSatisfy(\.isSettled)
    }
}

// MARK: - 物理零件

/// 阻尼弹簧（半隐式欧拉）
private struct Spring {
    var value: CGFloat = 0
    var velocity: CGFloat = 0
    var target: CGFloat = 0
    private(set) var acceleration: CGFloat = 0
    let stiffness: CGFloat
    let damping: CGFloat

    init(value: CGFloat = 0, stiffness: CGFloat, damping: CGFloat) {
        self.value = value
        self.target = value
        self.stiffness = stiffness
        self.damping = damping
    }

    mutating func step(_ dt: CGFloat) {
        acceleration = -stiffness * (value - target) - damping * velocity
        velocity += acceleration * dt
        value += velocity * dt
    }

    mutating func snap() {
        value = target
        velocity = 0
        acceleration = 0
    }

    var isSettled: Bool { abs(value - target) < 0.1 && abs(velocity) < 0.5 }
}

/// 一件衣服：衣夹沿绳子滑动（x），落到绳上的回弹（drop），以及挂在衣夹下的单摆（angle）。
private struct Node {
    var x: Spring
    var drop: Spring
    var angle: CGFloat = 0
    var angularVelocity: CGFloat = 0

    /// 单摆固有频率的平方（周期约 0.95 秒）
    private static let pendulumStiffness: CGFloat = 44
    private static let pendulumDamping: CGFloat = 2.8
    /// 衣夹水平加速度带动摆动的强度：滑得越猛，晃得越厉害
    private static let inertia: CGFloat = 0.0009

    init(x: CGFloat, drop: CGFloat) {
        self.x = Spring(value: x, stiffness: 260, damping: 26)
        var dropSpring = Spring(value: drop, stiffness: 320, damping: 15)
        dropSpring.target = 0
        self.drop = dropSpring
    }

    mutating func step(_ dt: CGFloat) {
        x.step(dt)
        drop.step(dt)
        let torque = -Self.pendulumStiffness * angle - Self.pendulumDamping * angularVelocity - Self.inertia * x.acceleration
        angularVelocity += torque * dt
        angle = min(max(angle + angularVelocity * dt, -0.6), 0.6)
    }

    mutating func snap() {
        x.snap()
        drop.snap()
        angle = 0
        angularVelocity = 0
    }

    var isSettled: Bool {
        x.isSettled && drop.isSettled && abs(angle) < 0.005 && abs(angularVelocity) < 0.03
    }
}

/// 绳子上的一次起伏：两端固定，在 x 附近最明显，衰减振荡。
private struct Ripple {
    var x: CGFloat
    var amplitude: CGFloat
    var age: CGFloat = 0

    static let spread: CGFloat = 240
    static let frequency: CGFloat = 2.3
    static let decay: CGFloat = 0.42
    static let lifetime: CGFloat = 1.8

    var displacement: CGFloat {
        amplitude * exp(-age / Self.decay) * sin(2 * .pi * Self.frequency * age)
    }
}
