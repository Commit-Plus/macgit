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

struct SidebarTagContextMenu: View {
    let tag: String
    let remoteNames: [String]
    let actions: SidebarTagSectionActions

    var body: some View {
        Button("Copy Tag Name to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tag, forType: .string)
        }

        Divider()

        Button("Checkout \(tag)") {
            actions.checkout(tag)
        }
        Button("Details...") {
            actions.showDetails(tag)
        }

        Divider()

        Button("Diff Against Current") {
            actions.diffAgainstCurrent(tag)
        }

        Divider()

        Menu("Push to") {
            if remoteNames.isEmpty {
                Text("No remotes configured")
            } else {
                ForEach(remoteNames.sorted(), id: \.self) { remote in
                    Button(remote) {
                        actions.pushToRemote(tag, remote)
                    }
                }
            }
        }
        .disabled(remoteNames.isEmpty)

        Menu("Force Push to") {
            if remoteNames.isEmpty {
                Text("No remotes configured")
            } else {
                ForEach(remoteNames.sorted(), id: \.self) { remote in
                    Button(remote, role: .destructive) {
                        actions.forcePushToRemote(tag, remote)
                    }
                }
            }
        }
        .disabled(remoteNames.isEmpty)

        Button("Delete \(tag)", role: .destructive) {
            actions.delete(tag)
        }
    }
}
