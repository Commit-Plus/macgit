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
import SwiftUI

struct SidebarTagRow: View {
    let row: BranchRowItem
    let expandedFolders: Set<String>
    let remoteNames: [String]
    let actions: SidebarTagSectionActions

    var body: some View {
        if row.isFolder {
            content
                .onTapGesture {
                    actions.toggleFolder(row.fullPath)
                }
        } else {
            content
                .tag(SidebarSelection.tag(row.fullPath))
                .onTapGesture {
                    actions.select(.tag(row.fullPath))
                }
                .onTapGesture(count: 2) {
                    actions.checkout(row.fullPath)
                }
                .contextMenu {
                    SidebarTagContextMenu(
                        tag: row.fullPath,
                        remoteNames: remoteNames,
                        actions: actions
                    )
                }
        }
    }

    private var content: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16)
                }
            }

            if row.isFolder {
                Image(systemName: expandedFolders.contains(row.fullPath) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            } else {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            }

            Text(row.name)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
