import SwiftUI

/// 面板的根视图：绳子、衣服、两端的按钮。拖放由外层的 RopeContainerView 用 AppKit 处理。
struct RopeView: View {
    let model: AppModel

    var body: some View {
        GeometryReader { proxy in
            RopeContent(model: model, width: proxy.size.width)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 布局算出目标位置，RopeSimulation 逐帧算出此刻的位置；静止后 TimelineView 暂停。
/// 分两层：会动的绳子和衣服逐帧重画；按钮、提示、鼠标交互区只随数据变化更新。
private struct RopeContent: View {
    let model: AppModel
    let width: CGFloat

    @State private var simulation = RopeSimulation()
    @Environment(\.rendersInteraction) private var rendersInteraction

    var body: some View {
        let layout = RopeLayout(width: width, count: model.store.items.count, expanded: model.isExpanded, gapIndex: model.dropGapIndex)
        let targets = RopeSimulation.Targets(
            width: width,
            sag: layout.sag,
            controlX: layout.controlX,
            isExpanded: model.isExpanded,
            clothes: model.store.items.enumerated().map { .init(id: $1.id, x: layout.x($0)) },
            ghostX: layout.gapX,
            isContinuous: model.isDragHinting || layout.gapIndex != nil
        )

        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !simulation.isRunning)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let _ = rendersInteraction ? simulation.advance(to: time, targets: targets) : simulation.snap(to: targets)
                RopeScene(model: model, simulation: simulation, layout: layout, width: width, time: time)
            }
            RopeControls(model: model, layout: layout, width: width) { id in
                simulation.nudge(id)
            }
        }
        .frame(width: width, height: RopeMetrics.expandedHeight, alignment: .topLeading)
        .onChange(of: targets) { simulation.wake() }
        .onAppear { simulation.wake() }
    }
}

/// 逐帧重画的部分：绳子、衣服、虚线衣服、拖拽提示。
private struct RopeScene: View {
    let model: AppModel
    let simulation: RopeSimulation
    let layout: RopeLayout
    let width: CGFloat
    let time: TimeInterval

    var body: some View {
        let store = model.store
        let basket = RopeControls.basketPoint(in: layout, width: width)

        ZStack(alignment: .topLeading) {
            DropGlow(isTargeted: model.isDropTargeted, width: width)

            RopeCanvas(points: simulation.ropePoints(), expansion: simulation.expansion, isHighlighted: model.isDropTargeted)
                .equatable()
                .frame(width: width, height: RopeMetrics.ropeCanvasHeight)

            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                let pose = simulation.pose(for: item.id) ?? RopeSimulation.Pose(x: layout.x(index), y: layout.ropeY(at: layout.x(index)), angle: 0)
                ClothesView(
                    item: item,
                    url: store.url(for: item.id),
                    isMissing: store.missing.contains(item.id),
                    isSelected: model.selection.contains(item.id),
                    isExpanded: model.isExpanded,
                    isHovered: model.hoveredID == item.id,
                    angle: pose.angle,
                    refreshToken: model.expandCount
                )
                // 正在被拖去别处的衣服在原位变淡
                .opacity(model.draggedIDs.contains(item.id) ? 0.35 : 1)
                .offset(x: pose.x - RopeMetrics.cardWidth / 2, y: pose.y - RopeMetrics.pinAboveRope)
                .zIndex(Double(index))
                .transition(.clothes(style: model.removalStyle, from: CGPoint(x: pose.x, y: pose.y),
                                     basket: basket, index: index))
            }

            if let pose = simulation.ghostPose {
                GhostClothes(count: model.dropCount, isReorder: model.isDraggingOut, angle: pose.angle, time: time)
                    .offset(x: pose.x - RopeMetrics.cardWidth / 2, y: pose.y - RopeMetrics.pinAboveRope)
                    .zIndex(Double(store.items.count) + 1)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }

            if model.isDragHinting && !model.isExpanded {
                DragHintTab(time: time)
                    .frame(width: width)
                    .offset(y: RopeMetrics.anchorY - RopeMetrics.pinAboveRope)
                    .zIndex(Double(store.items.count) + 2)
                    .transition(.offset(y: -36).combined(with: .opacity))
            }
        }
        .frame(width: width, height: RopeMetrics.expandedHeight, alignment: .topLeading)
    }
}

/// 不随动画逐帧变化的部分：两端按钮、空绳提示、提示条，以及每件衣服的鼠标交互区。
private struct RopeControls: View {
    let model: AppModel
    let layout: RopeLayout
    let width: CGFloat
    let onHover: (UUID) -> Void

    @Environment(\.rendersInteraction) private var rendersInteraction

    static func basketPoint(in layout: RopeLayout, width: CGFloat) -> CGPoint {
        let x = width - RopeMetrics.sideReserve / 2
        return CGPoint(x: x, y: layout.ropeY(at: x) + 28)
    }

    var body: some View {
        let store = model.store

        ZStack(alignment: .topLeading) {
            if rendersInteraction && model.isExpanded {
                hitAreas
            }

            if model.isExpanded {
                BasketButton(count: store.items.count, progress: model.collectProgress, bounce: model.basketBounce) {
                    model.collect()
                }
                .position(Self.basketPoint(in: layout, width: width))
                .transition(.scale(scale: 0.8).combined(with: .opacity))

                if !store.items.isEmpty && !model.isCollecting {
                    let takeDownX = RopeMetrics.sideReserve / 2
                    TakeDownAllButton(count: store.items.count) {
                        model.takeDownAll()
                    }
                    .position(x: takeDownX, y: layout.ropeY(at: takeDownX) + 28)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                if store.items.isEmpty && !model.isDropTargeted {
                    EmptyHint()
                        .position(x: width / 2, y: layout.ropeY(at: width / 2) + 36)
                        .transition(.opacity)
                }

                if let toast = model.toast {
                    let x = toastX(for: toast)
                    ToastLabel(toast: toast) {
                        model.performToastAction()
                    }
                    .position(x: x, y: min(layout.ropeY(at: x) + 110, RopeMetrics.expandedHeight - 13))
                    .zIndex(10_000)
                    .transition(.offset(y: 10).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    .id(toast.id)
                }
            }
        }
        .frame(width: width, height: RopeMetrics.expandedHeight, alignment: .topLeading)
    }

    /// 每件衣服的鼠标交互区：用布局的静止位置，不跟着摆动、回弹、悬停放大。
    /// 跟着动的话，判定区域每帧都在变，会不停触发“进入、离开”，衣服越晃越厉害。
    private var hitAreas: some View {
        ForEach(Array(model.store.items.enumerated()), id: \.element.id) { index, item in
            let x = layout.x(index)
            let path = model.store.url(for: item.id)?.path ?? item.path
            let tip = item.label.map { String(localized: "\($0)\n原文件：\(item.name)\n\(path)") } ?? path
            ClothesInteraction(id: item.id, path: tip, model: model) { hovering in
                model.setHovered(item.id, hovering)
                if hovering { onHover(item.id) }
            }
            .frame(width: RopeMetrics.cardWidth, height: ClothesView.height)
            .offset(x: x - RopeMetrics.cardWidth / 2, y: layout.ropeY(at: x) - RopeMetrics.pinAboveRope)
            .zIndex(Double(index))
        }
    }

    private func toastX(for toast: RopeToast) -> CGFloat {
        guard let index = toast.index, index < layout.count else { return width / 2 }
        return min(max(layout.x(index), 90), width - 90)
    }
}

// MARK: - 衣服离开的方式

extension AnyTransition {
    /// 新衣服淡入（落下和回弹由物理负责）；离开时按方式飞走，从左到右依次错开。
    @MainActor
    static func clothes(style: ClothesRemovalStyle, from point: CGPoint, basket: CGPoint, index: Int) -> AnyTransition {
        let removal: AnyTransition
        switch style {
        case .liftOff:
            // 从衣夹上摘下，往上飘走
            removal = .modifier(
                active: FlyAway(offset: CGSize(width: index.isMultiple(of: 2) ? -8 : 8, height: -70),
                                rotation: index.isMultiple(of: 2) ? -14 : 14, scale: 0.85, opacity: 0),
                identity: .identity
            )
            .animation(.spring(duration: 0.5, bounce: 0.15).delay(Double(index) * 0.025))
        case .intoBasket:
            // 沿弧线飞进右边的篮子
            removal = .modifier(
                active: FlyAway(offset: CGSize(width: basket.x - point.x, height: basket.y - point.y - 40),
                                rotation: 18, scale: 0.15, opacity: 0),
                identity: .identity
            )
            .animation(.spring(duration: 0.6, bounce: 0.1).delay(Double(index) * 0.04))
        }
        return .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.15)), removal: removal)
    }
}

private struct FlyAway: ViewModifier {
    let offset: CGSize
    let rotation: Double
    let scale: CGFloat
    let opacity: Double

    static let identity = FlyAway(offset: .zero, rotation: 0, scale: 1, opacity: 1)

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation), anchor: .top)
            .scaleEffect(scale, anchor: .top)
            .offset(offset)
            .opacity(opacity)
    }
}

// MARK: - 零件

/// 拖到晾衣台上时，绳子附近泛起一层光。
private struct DropGlow: View {
    let isTargeted: Bool
    let width: CGFloat

    var body: some View {
        LinearGradient(colors: [.accentColor.opacity(0.25), .accentColor.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(width: width, height: 80)
            .opacity(isTargeted ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: isTargeted)
            .allowsHitTesting(false)
    }
}

/// 拖着文件靠近时，在预备挂的位置出现一件虚线衣服：虚线缓缓流动、轻轻呼吸，表示“松手就挂在这里”。
///
/// 整件先在 App 里画成位图（drawingGroup）再交给系统合成。不这样做的话，虚线、图标、文字会由 WindowServer
/// 每帧重新光栅化，拖拽时把它占满，整台电脑都会卡。
private struct GhostClothes: View {
    let count: Int
    /// 拖的是绳上自己的衣服（调整位置），不是新文件
    let isReorder: Bool
    let angle: CGFloat
    let time: TimeInterval

    var body: some View {
        let breathe = 1 + 0.025 * sin(time * 5)
        VStack(spacing: -RopeMetrics.pinCardOverlap) {
            ClothesPin()
                .zIndex(1)
            ZStack {
                if count > 1 {
                    card
                        .rotationEffect(.degrees(8), anchor: .top)
                        .offset(x: 7, y: 2)
                        .opacity(0.5)
                }
                card
            }
            .scaleEffect(breathe, anchor: .top)
        }
        .frame(width: RopeMetrics.cardWidth)
        .padding(12)
        .drawingGroup()
        .padding(-12)
        .rotationEffect(.radians(angle), anchor: UnitPoint(x: 0.5, y: ClothesView.pivot))
        .allowsHitTesting(false)
    }

    private var title: String {
        switch (isReorder, count > 1) {
        case (true, true): String(localized: "\(count) 件放这里")
        case (true, false): String(localized: "放在这里")
        case (false, true): String(localized: "松手挂上 \(count) 件")
        case (false, false): String(localized: "松手挂上")
        }
    }

    private var card: some View {
        VStack(spacing: 6) {
            Image(systemName: isReorder ? "arrow.down.to.line" : "tshirt.fill")
                .font(.system(size: 22, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(Color.accentColor)
        .frame(width: RopeMetrics.cardWidth, height: ClothesCard.height)
        .background(RopePalette.paper.opacity(0.94), in: .rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor,
                              style: StrokeStyle(lineWidth: 2, dash: [5, 3], dashPhase: -time * 14))
        }
        .shadow(color: .accentColor.opacity(0.35), radius: 8, y: 3)
    }
}

/// 拖着文件靠近屏幕上方、绳子还收着时，从绳子正中垂下的小标签，轻轻上下晃，给拖拽一个停靠的目标。
private struct DragHintTab: View {
    let time: TimeInterval

    var body: some View {
        VStack(spacing: -RopeMetrics.pinCardOverlap) {
            ClothesPin()
                .zIndex(1)
            Label("拖到这里挂上", systemImage: "tshirt.fill")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Color.accentColor.gradient, in: .capsule)
                .shadow(color: .accentColor.opacity(0.5), radius: 6, y: 2)
                .offset(y: 1.5 * sin(time * 4))
        }
        .padding(10)
        .drawingGroup()
        .padding(-10)
        .allowsHitTesting(false)
    }
}

private struct ToastLabel: View {
    let toast: RopeToast
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(toast.text, systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
            if let actionTitle = toast.actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(RopePressStyle())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
        .allowsHitTesting(toast.actionTitle != nil)
    }
}

/// 按下时轻轻缩一下
private struct RopePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
    }
}

/// 收衣服、全部取下这类挂在绳子两端的胶囊按钮外观。
private extension View {
    func ropeCapsule() -> some View {
        font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }
}

/// 把绳上所有链接取下来（原文件不动），区别于收衣服。
private struct TakeDownAllButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("全部取下", systemImage: "tray.and.arrow.up")
                .ropeCapsule()
        }
        .buttonStyle(RopePressStyle())
        .help("把绳上的 \(count) 个链接全部取下，原文件留在原处")
    }
}

private struct BasketButton: View {
    let count: Int
    let progress: CollectProgress?
    /// 每次衣服飞进篮子时加一，篮子弹一下
    let bounce: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                    Text("\(progress.done)/\(progress.total)")
                        .monospacedDigit()
                } else {
                    Image(systemName: "basket.fill")
                        .foregroundStyle(RopePalette.woodDark)
                    Text("收衣服")
                }
            }
            .ropeCapsule()
        }
        .buttonStyle(RopePressStyle())
        .disabled(progress != nil || count == 0)
        .opacity(count == 0 && progress == nil ? 0.5 : 1)
        .keyframeAnimator(initialValue: 1.0, trigger: bounce) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.18, duration: 0.12)
                SpringKeyframe(0.94, duration: 0.15)
                SpringKeyframe(1.0, duration: 0.25)
            }
        }
        .help("把绳上的 \(count) 个文件按类型移动到一个目录")
    }
}

private struct EmptyHint: View {
    var body: some View {
        Text("把文件拖到屏幕上方就能挂上 · 拷贝的文件和图片会自动挂上")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .allowsHitTesting(false)
    }
}


