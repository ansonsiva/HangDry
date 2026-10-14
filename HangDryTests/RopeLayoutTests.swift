import CoreGraphics
import Testing

struct RopeLayoutTests {
    @Test func insertionIndexFollowsCursor() {
        let layout = RopeLayout(width: 1200, count: 3, expanded: true)
        #expect(layout.insertionIndex(at: 0) == 0)
        #expect(layout.insertionIndex(at: (layout.x(0) + layout.x(1)) / 2) == 1)
        #expect(layout.insertionIndex(at: (layout.x(1) + layout.x(2)) / 2) == 2)
        #expect(layout.insertionIndex(at: 1200) == 3)
    }

    @Test func gapPushesLaterClothesOneSlotRight() {
        let layout = RopeLayout(width: 1200, count: 3, expanded: true, gapIndex: 1)
        let gapX = try! #require(layout.gapX)
        #expect(layout.x(0) < gapX)
        #expect(layout.x(1) - gapX == layout.slot)
        #expect(layout.x(2) - layout.x(1) == layout.slot)
    }

    @Test func ropeSagsDeepestAtTheGap() {
        let plain = RopeLayout(width: 1200, count: 3, expanded: true)
        let pulled = RopeLayout(width: 1200, count: 3, expanded: true, gapIndex: 0)
        let gapX = try! #require(pulled.gapX)

        #expect(pulled.ropeY(at: gapX) > plain.ropeY(at: gapX))
        #expect(pulled.ropeY(at: 0) == RopeMetrics.anchorY)
        #expect(abs(pulled.ropeY(at: 1200) - RopeMetrics.anchorY) < 0.001)
        // 最低点偏向拖拽位置一侧
        #expect(pulled.ropeY(at: 400) > pulled.ropeY(at: 800))
    }

    @Test func collapsedRopeIsStraight() {
        let layout = RopeLayout(width: 1200, count: 5, expanded: false)
        #expect(layout.ropeY(at: 600) == RopeMetrics.anchorY)
    }
}
