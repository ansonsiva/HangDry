import SwiftUI

enum RopePalette {
    // 本色棉麻绳
    static let rope = Color(red: 0.74, green: 0.62, blue: 0.46)
    static let ropeShade = Color(red: 0.50, green: 0.38, blue: 0.26)
    static let ropeHighlight = Color(red: 0.94, green: 0.87, blue: 0.74)
    // 榉木衣夹
    static let woodLight = Color(red: 0.96, green: 0.83, blue: 0.62)
    static let woodMid = Color(red: 0.87, green: 0.69, blue: 0.46)
    static let woodDark = Color(red: 0.72, green: 0.53, blue: 0.33)
    static let brass = Color(red: 0.80, green: 0.66, blue: 0.36)
    static let paper = Color(red: 0.995, green: 0.99, blue: 0.975)
    static let paperShade = Color(red: 0.965, green: 0.955, blue: 0.93)
}

/// 三股拧成的麻绳：投影、本体、下侧暗部、斜向拧纹、上侧高光，两端各一个铜环。
struct RopeCanvas: View, Equatable {
    let points: [CGPoint]
    /// 0 收起（细绳），1 展开（粗绳）
    let expansion: CGFloat
    let isHighlighted: Bool

    /// 绳子形状几乎没变时（比如只有衣服在摆）跳过重画
    nonisolated static func == (lhs: RopeCanvas, rhs: RopeCanvas) -> Bool {
        guard lhs.isHighlighted == rhs.isHighlighted,
              abs(lhs.expansion - rhs.expansion) < 0.01,
              lhs.points.count == rhs.points.count else { return false }
        return zip(lhs.points, rhs.points).allSatisfy { abs($0.y - $1.y) < 0.05 && abs($0.x - $1.x) < 0.05 }
    }

    var body: some View {
        Canvas { context, _ in
            guard points.count > 1 else { return }
            let thickness = 2.2 + 2.0 * expansion
            var path = Path()
            path.addLines(points)
            let round = StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round)

            // 落在背景上的软投影：几层半透明粗线叠出来，比模糊滤镜便宜得多（每帧都要画）
            var shadow = context
            shadow.translateBy(x: 0, y: 1.5 + 2 * expansion)
            for (extra, alpha) in [(4.0, 0.05), (2.0, 0.08), (0.5, 0.12)] {
                shadow.stroke(path, with: .color(.black.opacity(alpha)),
                              style: StrokeStyle(lineWidth: thickness + extra, lineCap: .round, lineJoin: .round))
            }

            if isHighlighted {
                for (extra, alpha) in [(12.0, 0.12), (7.0, 0.2), (3.5, 0.35)] {
                    context.stroke(path, with: .color(.accentColor.opacity(alpha)),
                                   style: StrokeStyle(lineWidth: thickness + extra, lineCap: .round, lineJoin: .round))
                }
            }

            context.stroke(path, with: .color(RopePalette.rope), style: round)

            // 下侧暗部
            var underside = context
            underside.translateBy(x: 0, y: thickness * 0.24)
            underside.stroke(path, with: .color(RopePalette.ropeShade.opacity(0.55)),
                             style: StrokeStyle(lineWidth: thickness * 0.45, lineCap: .round, lineJoin: .round))

            // 拧纹：上下两半各一道虚线，彼此错开半拍，看起来像一股股斜着拧过去
            if thickness > 3 {
                let strand = StrokeStyle(lineWidth: thickness * 0.42, lineCap: .butt, lineJoin: .round, dash: [1.1, 3.1])
                var upper = context
                upper.translateBy(x: 0, y: -thickness * 0.2)
                upper.stroke(path, with: .color(RopePalette.ropeShade.opacity(0.55)), style: strand)
                var lower = context
                lower.translateBy(x: 0, y: thickness * 0.2)
                var shifted = strand
                shifted.dashPhase = 1.6
                lower.stroke(path, with: .color(RopePalette.ropeShade.opacity(0.55)), style: shifted)
            }

            // 上侧高光
            var highlight = context
            highlight.translateBy(x: 0, y: -thickness * 0.22)
            highlight.stroke(path, with: .color(RopePalette.ropeHighlight.opacity(0.75)),
                             style: StrokeStyle(lineWidth: max(thickness * 0.28, 0.8), lineCap: .round, lineJoin: .round))

            // 两端的铜环
            if let first = points.first, let last = points.last {
                for end in [first, last] {
                    let center = CGPoint(x: min(max(end.x, 5), last.x - 5), y: end.y)
                    let ring = Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
                    context.stroke(ring, with: .color(RopePalette.brass), lineWidth: 1.8)
                    context.stroke(ring.offsetBy(dx: -0.4, dy: -0.4), with: .color(.white.opacity(0.5)), lineWidth: 0.6)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 木头衣夹：两片榉木中间夹一圈金属弹簧，绳子从上部穿过。
struct ClothesPin: View {
    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0.7) {
                UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3.5, bottomTrailingRadius: 1, topTrailingRadius: 1)
                    .fill(LinearGradient(colors: [RopePalette.woodLight, RopePalette.woodMid], startPoint: .leading, endPoint: .trailing))
                UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1, bottomTrailingRadius: 3.5, topTrailingRadius: 3)
                    .fill(LinearGradient(colors: [RopePalette.woodMid, RopePalette.woodDark], startPoint: .leading, endPoint: .trailing))
            }
            // 两片中缝
            Rectangle()
                .fill(.black.opacity(0.22))
                .frame(width: 0.7)
            // 金属弹簧
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.62), Color(white: 0.78)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                .frame(width: RopeMetrics.pinWidth + 3, height: 3.6)
                .offset(y: RopeMetrics.pinAboveRope + 4)
        }
        .frame(width: RopeMetrics.pinWidth, height: RopeMetrics.pinHeight)
        .shadow(color: .black.opacity(0.3), radius: 1.2, y: 1)
        .allowsHitTesting(false)
    }
}
