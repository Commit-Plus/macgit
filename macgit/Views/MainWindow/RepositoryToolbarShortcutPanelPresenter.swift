//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import AppKit
import SwiftUI

struct RepositoryToolbarShortcutPanelPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let pinnedShortcuts: [RepositoryToolbarShortcut]
    let isActionDisabled: (RepositoryToolbarShortcut) -> Bool
    let onPerformAction: (RepositoryToolbarShortcut) -> Void
    let onSetPinned: (RepositoryToolbarShortcut, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onLayout = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.updateFrame(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.update(using: self, from: nsView)
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    private func makePanelContent() -> RepositoryToolbarShortcutPanel {
        RepositoryToolbarShortcutPanel(
            pinnedShortcuts: pinnedShortcuts,
            isActionDisabled: isActionDisabled,
            onPerformAction: onPerformAction,
            onSetPinned: onSetPinned,
            onDismiss: { isPresented = false }
        )
    }

    final class Coordinator {
        private static let panelWidth: CGFloat = 280
        private static let toolbarBottomSpacing: CGFloat = 4

        private weak var parentWindow: NSWindow?
        private weak var anchorView: AnchorView?
        private var panel: NSPanel?
        private var windowObservers: [NSObjectProtocol] = []

        func update(
            using presenter: RepositoryToolbarShortcutPanelPresenter,
            from anchorView: AnchorView
        ) {
            self.anchorView = anchorView

            guard presenter.isPresented else {
                dismiss()
                return
            }

            guard let window = anchorView.window else {
                DispatchQueue.main.async { [weak self, weak anchorView] in
                    guard let self, let anchorView else { return }
                    self.update(using: presenter, from: anchorView)
                }
                return
            }

            let panel = panel ?? makePanel()
            if let hostingView = panel.contentView as? NSHostingView<RepositoryToolbarShortcutPanel> {
                hostingView.rootView = presenter.makePanelContent()
            } else {
                let hostingView = NSHostingView(rootView: presenter.makePanelContent())
                hostingView.wantsLayer = true
                hostingView.layer?.cornerRadius = RepositoryToolbarShortcutPanel.cornerRadius
                hostingView.layer?.cornerCurve = .continuous
                hostingView.layer?.maskedCorners = [
                    .layerMinXMinYCorner,
                    .layerMinXMaxYCorner,
                ]
                hostingView.layer?.masksToBounds = true
                panel.contentView = hostingView
            }

            if parentWindow !== window {
                removeFromParent()
                parentWindow = window
                window.addChildWindow(panel, ordered: .above)
                observeWindow(window)
            }

            self.panel = panel
            updateFrame(from: anchorView)
            panel.orderFront(nil)
        }

        func updateFrame(from anchorView: AnchorView) {
            guard let panel,
                  let window = anchorView.window,
                  parentWindow === window else { return }

            let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let anchorRectOnScreen = window.convertToScreen(anchorRectInWindow)
            let top = min(
                window.frame.maxY,
                anchorRectOnScreen.minY - Self.toolbarBottomSpacing
            )
            let height = max(0, top - window.frame.minY)
            panel.setFrame(
                NSRect(
                    x: window.frame.maxX - Self.panelWidth,
                    y: window.frame.minY,
                    width: Self.panelWidth,
                    height: height
                ),
                display: true
            )
        }

        func dismiss() {
            removeFromParent()
            panel?.orderOut(nil)
            panel = nil
            anchorView = nil
        }

        private func makePanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.becomesKeyOnlyIfNeeded = true
            return panel
        }

        private func observeWindow(_ window: NSWindow) {
            removeWindowObservers()
            let center = NotificationCenter.default
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                windowObservers.append(
                    center.addObserver(
                        forName: name,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        guard let self, let anchorView = self.anchorView else { return }
                        self.updateFrame(from: anchorView)
                    }
                )
            }
        }

        private func removeFromParent() {
            if let parentWindow, let panel {
                parentWindow.removeChildWindow(panel)
            }
            parentWindow = nil
            removeWindowObservers()
        }

        private func removeWindowObservers() {
            let center = NotificationCenter.default
            for observer in windowObservers {
                center.removeObserver(observer)
            }
            windowObservers.removeAll()
        }

        deinit {
            removeWindowObservers()
        }
    }

    final class AnchorView: NSView {
        var onLayout: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.onLayout?()
            }
        }

        override func layout() {
            super.layout()
            DispatchQueue.main.async { [weak self] in
                self?.onLayout?()
            }
        }
    }
}
