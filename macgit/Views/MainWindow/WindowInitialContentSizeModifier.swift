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

struct WindowInitialContentSizeModifier: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        scheduleResize(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleResize(for: nsView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(width: width, height: height)
    }

    private func scheduleResize(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.resizeIfNeeded(window: view.window)
        }
    }

    final class Coordinator {
        private let width: CGFloat
        private let height: CGFloat
        private var didResizeWindow = false

        init(width: CGFloat, height: CGFloat) {
            self.width = width
            self.height = height
        }

        func resizeIfNeeded(window: NSWindow?) {
            guard !didResizeWindow,
                  let window,
                  let screen = window.screen ?? NSScreen.main else {
                return
            }

            let visibleFrame = screen.visibleFrame
            let contentSize = NSSize(
                width: min(width, visibleFrame.width),
                height: min(height, visibleFrame.height)
            )
            let windowSize = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: contentSize)
            ).size
            let centeredFrame = NSRect(
                x: visibleFrame.midX - windowSize.width / 2,
                y: visibleFrame.midY - windowSize.height / 2,
                width: windowSize.width,
                height: windowSize.height
            )

            didResizeWindow = true
            window.setFrame(centeredFrame, display: true)
        }
    }
}
