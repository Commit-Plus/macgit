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

extension Notification.Name {
    static let fileMenuAction = Notification.Name("macgit.fileMenuAction")
}

struct RepositoryFileCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.repositoryWindowCommandState) private var commandState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab", action: openNewTab)
                .keyboardShortcut("t", modifiers: .command)

            Button("New Window", action: openNewWindow)
                .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Open Repository…") {
                postFileAction(.openRepository)
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Clone Repository…") {
                postFileAction(.cloneRepository)
            }
        }

        CommandGroup(after: .newItem) {
            Menu("Open Recent") {
                let recents = Array(RecentRepositoriesStore.shared.repositories.prefix(10))
                if recents.isEmpty {
                    Text("No Recent Repositories")
                } else {
                    ForEach(recents) { repo in
                        Button(repo.name) {
                            postFileAction(.openRecent(repo.url))
                        }
                    }
                }
            }

            Divider()

            Button("Close Repository") {
                postFileAction(.closeRepository)
            }
            .disabled(commandState?.hasOpenRepository != true)

            Button("Close Tab", action: closeTab)
                .keyboardShortcut("w", modifiers: .command)
                .disabled(commandState == nil || commandState?.hasActiveOperation == true)

            Button("Close Window", action: closeWindow)
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(commandState == nil || commandState?.hasActiveOperation == true)
        }
    }

    private func openNewTab() {
        guard NSApp.keyWindow != nil else {
            openNewWindow()
            return
        }
        let handled = NSApp.sendAction(
            #selector(NSResponder.newWindowForTab(_:)),
            to: nil,
            from: nil
        )
        if !handled {
            openNewWindow()
        }
    }

    private func openNewWindow() {
        openWindow(
            id: "main",
            value: RepositoryWindowRequest.repositoryPicker()
        )
    }

    private func closeTab() {
        NSApp.keyWindow?.performClose(nil)
    }

    private func closeWindow() {
        guard let keyWindow = NSApp.keyWindow else { return }
        let windows = keyWindow.tabGroup?.windows ?? [keyWindow]
        for window in windows.reversed() {
            window.performClose(nil)
        }
    }

    private func postFileAction(_ action: FileMenuAction) {
        WindowScopedNotification.post(
            name: .fileMenuAction,
            userInfo: ["action": action]
        )
    }
}
