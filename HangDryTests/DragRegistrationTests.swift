import AppKit
import SwiftUI
import Testing

/// 拖拽只能由最外层的 RopeContainerView 接收。
/// 里面任何一层也注册了拖拽类型，拖到它上面时接收方就会来回切换，空位开合不停。
@MainActor
struct DragRegistrationTests {
    @Test func onlyContainerAcceptsDragsWhenExpandedWithClothes() throws {
        let sandbox = try Sandbox()
        let store = RopeStore(directory: sandbox.url("Support"))
        store.hang(try ["a.mp4", "b.wav", "c.png"].map { try sandbox.file($0) }, origin: .dropped)
        let model = AppModel(store: store)
        model.isExpanded = true

        let host = FirstMouseHostingView(rootView: RopeView(model: model))
        host.sizingOptions = []
        let container = RopeContainerView(host: host)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: RopeMetrics.expandedHeight),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        // 让 SwiftUI 把 NSViewRepresentable 建出来
        for _ in 0..<5 {
            RunLoop.main.run(until: .now.addingTimeInterval(0.05))
            container.layoutSubtreeIfNeeded()
        }

        var registered: [String] = []
        func walk(_ view: NSView) {
            if view !== container, !view.registeredDraggedTypes.isEmpty {
                registered.append("\(type(of: view)): \(view.registeredDraggedTypes.prefix(3))")
            }
            view.subviews.forEach(walk)
        }
        walk(container)

        let interactionViews = allSubviews(of: container).filter { $0 is ClothesInteractionView }
        #expect(interactionViews.count == 3, "展开后每件衣服应该有一个交互视图")
        #expect(registered.isEmpty, "这些视图也注册了拖拽：\(registered)")
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(allSubviews(of:))
    }
}
