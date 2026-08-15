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

struct RepositoryToolbarShortcutPanel: View {
    static let cornerRadius: CGFloat = 28

    let pinnedShortcuts: [RepositoryToolbarShortcut]
    let isActionDisabled: (RepositoryToolbarShortcut) -> Bool
    let onPerformAction: (RepositoryToolbarShortcut) -> Void
    let onSetPinned: (RepositoryToolbarShortcut, Bool) -> Void
    let onDismiss: () -> Void

    private var pinnedSet: Set<RepositoryToolbarShortcut> {
        Set(pinnedShortcuts)
    }

    private var pinLimitReached: Bool {
        pinnedShortcuts.count >= RepositoryToolbarShortcut.maximumPinnedCount
    }

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.cornerRadius,
            bottomLeadingRadius: Self.cornerRadius
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .opacity(0.65)

            VStack(spacing: 10) {
                ForEach(RepositoryToolbarShortcut.allCases) { shortcut in
                    shortcutRow(shortcut)
                }
            }
            .padding(12)

            Spacer(minLength: 12)

            Text("Pin up to \(RepositoryToolbarShortcut.maximumPinnedCount) shortcuts to the toolbar.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(
            .regular.tint(Color(nsColor: .controlBackgroundColor).opacity(0.24)),
            in: panelShape
        )
        .overlay {
            panelShape
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(panelShape)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Toolbar Shortcuts")
                    .font(.headline)
            }

            Spacer()

            Button("Close toolbar shortcuts", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Close")
        }
        .padding(16)
    }

    private func shortcutRow(_ shortcut: RepositoryToolbarShortcut) -> some View {
        let isPinned = pinnedSet.contains(shortcut)

        return HStack(spacing: 10) {
            Button(action: { onPerformAction(shortcut) }) {
                Label(shortcut.title, systemImage: shortcut.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isActionDisabled(shortcut))

            Button(
                isPinned ? "Unpin \(shortcut.title)" : "Pin \(shortcut.title)",
                systemImage: isPinned ? "pin.fill" : "pin"
            ) {
                onSetPinned(shortcut, !isPinned)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .controlSize(.small)
            .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            .disabled(!isPinned && pinLimitReached)
            .help(isPinned ? "Unpin from Toolbar" : pinLimitReached ? "Unpin another shortcut first" : "Pin to Toolbar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.primary.opacity(0.055))
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}
