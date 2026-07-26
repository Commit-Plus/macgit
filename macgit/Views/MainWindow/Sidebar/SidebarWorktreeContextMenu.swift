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

struct SidebarWorktreeContextMenu: View {
    let entry: WorktreeEntry
    let isCurrentRepositoryWorktree: Bool
    let onOpenInNewWindow: () -> Void
    let onOpenInTerminal: () -> Void
    let onEditLabel: () -> Void
    let onClearLabel: () -> Void
    let onEditLock: () -> Void
    let onUnlock: () -> Void
    let onMove: () -> Void
    let onSwitchBranch: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Group {
            Button("Open in New Window", action: onOpenInNewWindow)

            Button("Open in Terminal", action: onOpenInTerminal)

            Divider()

            Button(entry.label == nil ? "Set Label..." : "Edit Label...", action: onEditLabel)

            if entry.label != nil {
                Button("Clear Label", action: onClearLabel)
            }

            Divider()

            if !isCurrentRepositoryWorktree {
                if entry.isLocked {
                    Button("Unlock Worktree", action: onUnlock)
                } else {
                    Button("Lock Worktree...", action: onEditLock)
                }

                Button("Rename/Move Worktree...", action: onMove)

                Button("Switch Branch...", action: onSwitchBranch)

                Divider()

                Button("Remove Worktree...", role: .destructive, action: onRemove)

                Divider()
            }

            Button("Copy Path to Clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.path.path, forType: .string)
            }
        }
    }
}
