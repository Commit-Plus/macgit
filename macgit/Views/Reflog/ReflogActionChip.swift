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

struct ReflogActionChip: View {
    let action: String

    var body: some View {
        Text(action)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.2), in: Capsule())
            .overlay {
                Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 0.5)
            }
            .help(action)
            .accessibilityLabel("Action: \(action)")
    }

    private var tint: Color {
        // Keep variants such as commit (amend) and rebase (finish)
        // in the same color family while preserving their full labels.
        let kind = action.lowercased().split { $0.isWhitespace || $0 == "(" }.first
        switch kind {
        case "commit": return .green
        case "checkout", "switch": return .blue
        case "reset": return .red
        case "rebase": return .purple
        case "merge": return .orange
        case "cherry-pick": return .pink
        case "revert": return .brown
        case "pull": return .teal
        case "fetch": return .cyan
        case "branch": return .indigo
        case "stash": return .yellow
        case "clone": return .mint
        default: return .gray
        }
    }
}
