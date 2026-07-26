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

struct SidebarWorkspaceSection: View {
    let onRequestSearch: () -> Void

    var body: some View {
        Section(SidebarSection.workspace.rawValue) {
            ForEach(SidebarSection.workspace.items) { item in
                if item == .search {
                    Label(item.rawValue, systemImage: item.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onRequestSearch()
                        }
                } else {
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(SidebarSelection.item(item))
                }
            }
        }
    }
}
