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

struct RepositoryWindowReader: NSViewRepresentable {
    let repositoryWindowContext: RepositoryWindowContext
    let title: String

    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView(
            repositoryWindowContext: repositoryWindowContext,
            title: title
        )
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.repositoryWindowContext = repositoryWindowContext
        nsView.title = title
        nsView.configureWindow()
    }

    static func dismantleNSView(_ nsView: WindowReaderView, coordinator: Void) {
        if nsView.repositoryWindowContext.window === nsView.window {
            nsView.repositoryWindowContext.window = nil
        }
    }

    final class WindowReaderView: NSView {
        var repositoryWindowContext: RepositoryWindowContext
        var title: String

        init(repositoryWindowContext: RepositoryWindowContext, title: String) {
            self.repositoryWindowContext = repositoryWindowContext
            self.title = title
            super.init(frame: .zero)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            guard let window else { return }
            repositoryWindowContext.window = window
            window.tabbingIdentifier = "com.commitplus.macgit.repository"
            window.tabbingMode = .automatic
            window.title = title
            window.titleVisibility = .hidden
        }
    }
}
