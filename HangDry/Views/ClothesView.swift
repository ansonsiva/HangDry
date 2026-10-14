import SwiftUI

extension EnvironmentValues {
    /// 离屏渲染（截图、测试）时关掉 AppKit 交互层和物理动画，ImageRenderer 画不了 NSView。
    @Entry var rendersInteraction = true
}

extension FileKind {
    var tint: Color {
        switch self {
        case .video: .purple
        case .audio: .orange
        case .image: .green
        case .document: .blue
        case .project: .pink
        case .archive: .brown
        case .folder: .teal
        case .other: .gray
        }
    }
}

/// 绳上的一件衣服：木头衣夹夹着一张卡片。位置和摆动角度由 RopeSimulation 每帧给出。
/// 只负责画；鼠标交互在 RopeScene 里单独一层，放在衣服的静止位置上，不跟着摆动。
struct ClothesView: View {
    let item: HungItem
    let url: URL?
    let isMissing: Bool
    let isSelected: Bool
    let isExpanded: Bool
    let isHovered: Bool
    /// 摆动角度（弧度），以绳子穿过衣夹的位置为轴
    let angle: CGFloat
    /// 每次绳子展开时变化，借此检查文件有没有被改过、需要重新生成缩略图
    var refreshToken = 0

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: -RopeMetrics.pinCardOverlap) {
            ClothesPin()
                .scaleEffect(isExpanded ? 1 : 0.7, anchor: .top)
                .zIndex(1)
            // 卡片内容不随摆动变化：相等就跳过重画，摆动时只旋转缓存好的图层
            ClothesCard(
                name: item.displayName, kind: item.kind, isCopy: item.isCopy,
                image: isMissing ? nil : (thumbnail ?? ThumbnailCache.shared.cached(for: item.id)),
                isMissing: isMissing, isSelected: isSelected, isLifted: isHovered
            )
            .equatable()
            .scaleEffect(isHovered ? 1.05 : 1, anchor: .top)
            .animation(.spring(duration: 0.3, bounce: 0.4), value: isHovered)
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(isExpanded ? 1 : 0.4, anchor: .top)
        }
        .frame(width: RopeMetrics.cardWidth)
        .rotationEffect(.radians(angle), anchor: UnitPoint(x: 0.5, y: Self.pivot))
        .task(id: ThumbnailRequest(item: item.id, url: url, refresh: refreshToken)) {
            guard let url else { return }
            thumbnail = await ThumbnailCache.shared.thumbnail(for: url, item: item.id)
        }
    }

    /// 整件衣服（衣夹加卡片）的高度
    static let height = RopeMetrics.pinHeight - RopeMetrics.pinCardOverlap + ClothesCard.height
    /// 摆动轴：绳子穿过衣夹的位置，占整件衣服高度的比例
    static let pivot = RopeMetrics.pinAboveRope / height
}

/// 卡片本身：拍立得式的纸卡，带缩略图、文件名和缝了线的彩色下摆。
struct ClothesCard: View, Equatable {
    let name: String
    let kind: FileKind
    let isCopy: Bool
    let image: NSImage?
    let isMissing: Bool
    let isSelected: Bool
    let isLifted: Bool

    static let height: CGFloat = 92

    nonisolated static func == (lhs: ClothesCard, rhs: ClothesCard) -> Bool {
        lhs.name == rhs.name && lhs.kind == rhs.kind && lhs.isCopy == rhs.isCopy && lhs.image === rhs.image
            && lhs.isMissing == rhs.isMissing && lhs.isSelected == rhs.isSelected && lhs.isLifted == rhs.isLifted
    }

    var body: some View {
        VStack(spacing: 5) {
            preview
                .frame(width: 66, height: 46)
                .clipShape(.rect(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.07), lineWidth: 0.5))
            Text(name)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.black.opacity(0.72))
                .frame(width: 66, height: 22, alignment: .top)
        }
        .padding(.horizontal, 5)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .frame(height: Self.height, alignment: .top)
        .background(
            LinearGradient(colors: [RopePalette.paper, RopePalette.paperShade], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 5)
        )
        .overlay(alignment: .bottom) { hem }
        .overlay(alignment: .topLeading) {
            if isCopy {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.black.opacity(0.35))
                    .padding(4)
                    .help("这是挂绳时复制的副本")
            }
        }
        .overlay(alignment: .topTrailing) {
            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                    .padding(4)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
        }
        .saturation(isMissing ? 0 : 1)
        .opacity(isMissing ? 0.6 : 1)
        // 贴身的接触阴影 + 投影。连同卡片一起渲染成一张图层，摆动时只是旋转这张图，不用每帧重画阴影
        .shadow(color: .black.opacity(0.14), radius: 0.6, y: 0.6)
        .shadow(color: .black.opacity(isLifted ? 0.32 : 0.24), radius: isLifted ? 8 : 4, y: isLifted ? 7 : 3)
        .padding(10)
        .drawingGroup()
        .padding(-10)
    }

    /// 衣服下摆：一道缝线加一条表示文件类型的色边
    private var hem: some View {
        VStack(spacing: 2) {
            Line()
                .stroke(kind.tint.opacity(0.55), style: StrokeStyle(lineWidth: 0.8, dash: [2, 1.6]))
                .frame(height: 1)
                .padding(.horizontal, 6)
            UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                .fill(kind.tint.gradient)
                .frame(height: 4)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(white: 0.95)
                Circle()
                    .fill(kind.tint.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: isMissing ? "questionmark.folder" : kind.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isMissing ? .gray : kind.tint)
            }
        }
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct ThumbnailRequest: Equatable {
    let item: UUID
    let url: URL?
    let refresh: Int
}
