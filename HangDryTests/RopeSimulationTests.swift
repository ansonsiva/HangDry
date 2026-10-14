import Foundation
import Testing

@MainActor
struct RopeSimulationTests {
    private let id = UUID()

    private func targets() -> RopeSimulation.Targets {
        RopeSimulation.Targets(width: 1200, sag: 20, controlX: 600, isExpanded: true,
                               clothes: [.init(id: id, x: 600)], ghostX: nil, isContinuous: false)
    }

    /// 推进 `seconds` 秒，期间每帧都“碰”一下（模拟鼠标判定反复触发），返回最大摆角。
    private func maxAngle(nudgingEveryFrame: Bool, seconds: Double) -> CGFloat {
        let simulation = RopeSimulation()
        var time: TimeInterval = 1000
        simulation.advance(to: time, targets: targets())
        simulation.nudge(id)
        var peak: CGFloat = 0
        for _ in 0..<Int(seconds * 60) {
            time += 1.0 / 60
            if nudgingEveryFrame { simulation.nudge(id) }
            simulation.advance(to: time, targets: targets())
            peak = max(peak, abs(simulation.pose(for: id)?.angle ?? 0))
        }
        return peak
    }

    @Test func repeatedHoverDoesNotPumpTheSwing() {
        let single = maxAngle(nudgingEveryFrame: false, seconds: 0.7)
        let spammed = maxAngle(nudgingEveryFrame: true, seconds: 0.7)
        #expect(single > 0.01, "碰一下应该会晃")
        #expect(abs(spammed - single) < 0.001, "冷却期内反复碰不应该越晃越大")
        #expect(single < 0.2, "鼠标碰一下只是轻轻晃")
    }

    @Test func settlesAfterNudge() {
        let simulation = RopeSimulation()
        var time: TimeInterval = 1000
        simulation.advance(to: time, targets: targets())
        simulation.nudge(id)
        for _ in 0..<(60 * 4) {
            time += 1.0 / 60
            simulation.advance(to: time, targets: targets())
        }
        #expect(abs(simulation.pose(for: id)?.angle ?? 1) < 0.003)
    }
}
