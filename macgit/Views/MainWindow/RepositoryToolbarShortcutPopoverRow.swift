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

struct RepositoryToolbarShortcutPopoverRow: View {
    let shortcut: RepositoryToolbarShortcut
    let isPinned: Bool
    let isActionDisabled: Bool
    let isPinDisabled: Bool
    let onPerformAction: () -> Void
    let onSetPinned: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPerformAction) {
                Label(shortcut.title, systemImage: shortcut.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isActionDisabled)

            Button(
                isPinned ? "Unpin \(shortcut.title)" : "Pin \(shortcut.title)",
                systemImage: isPinned ? "pin.fill" : "pin"
            ) {
                onSetPinned(!isPinned)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .frame(width: 32, height: 28)
            .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            .disabled(isPinDisabled)
            .help(pinHelp)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.primary.opacity(0.06))
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private var pinHelp: String {
        if isPinned {
            "Unpin from Toolbar"
        } else if isPinDisabled {
            "Unpin another shortcut first"
        } else {
            "Pin to Toolbar"
        }
    }
}
