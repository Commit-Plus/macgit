import SwiftUI

struct SyncedScrollView<Content: View>: View {
    let id: String
    let controller: SyncedScrollController
    let axes: Axis.Set
    let showsIndicators: Bool
    @ViewBuilder let content: Content

    init(
        id: String,
        controller: SyncedScrollController,
        axes: Axis.Set = [.horizontal, .vertical],
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.controller = controller
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content
                .background(
                    SyncedScrollConnector(id: id, controller: controller)
                )
        }
    }
}

private struct SyncedScrollConnector: NSViewRepresentable {
    let id: String
    let controller: SyncedScrollController

    func makeNSView(context: Context) -> SyncedScrollBridgeView {
        let view = SyncedScrollBridgeView()
        view.configure(id: id, controller: controller)
        return view
    }

    func updateNSView(_ nsView: SyncedScrollBridgeView, context: Context) {
        nsView.configure(id: id, controller: controller)
    }

    static func dismantleNSView(_ nsView: SyncedScrollBridgeView, coordinator: ()) {
        nsView.detach()
    }
}

private final class SyncedScrollBridgeView: NSView {
    private var id: String?
    private weak var controller: SyncedScrollController?
    private weak var scrollView: NSScrollView?

    func configure(id: String, controller: SyncedScrollController) {
        if self.id != id {
            detach()
        }

        self.id = id
        self.controller = controller
        resolveScrollView()
    }

    func detach() {
        guard let id, let scrollView else { return }
        controller?.unregister(id: id, scrollView: scrollView)
        self.scrollView = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveScrollView()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        resolveScrollView()
    }

    private func resolveScrollView() {
        DispatchQueue.main.async { [weak self] in
            self?.attachToEnclosingScrollView()
        }
    }

    private func attachToEnclosingScrollView() {
        guard let id, let controller else { return }
        guard let enclosingScrollView else { return }

        if scrollView !== enclosingScrollView {
            if let scrollView {
                controller.unregister(id: id, scrollView: scrollView)
            }

            scrollView = enclosingScrollView
            controller.register(enclosingScrollView, id: id)
        }
    }
}
