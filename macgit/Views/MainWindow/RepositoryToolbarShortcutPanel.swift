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
    static let panelWidth: CGFloat = 340
    static let cornerRadius: CGFloat = 28

    let pinnedShortcuts: [RepositoryToolbarShortcut]
    let isActionDisabled: (RepositoryToolbarShortcut) -> Bool
    let onPerformAction: (RepositoryToolbarShortcut) -> Void
    let onSetPinned: (RepositoryToolbarShortcut, Bool) -> Void
    let onDismiss: () -> Void
    @State private var selectedTab: PanelTab = .shortcuts

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
            tabSelector
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Group {
                switch selectedTab {
                case .shortcuts:
                    shortcutsContent
                case .chat:
                    chatPlaceholder
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Self.panelWidth)
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
                Text("Toolbar")
                    .font(.headline)
            }

            Spacer()

            Button("Close toolbar shortcuts", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.small)
                .frame(width: 44, height: 32)
                .background(controlBackground(cornerRadius: 11))
                .help("Close")
        }
        .padding(16)
    }

    private var tabSelector: some View {
        HStack(spacing: 6) {
            ForEach(PanelTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .glassEffect(
            .regular.tint(Color(nsColor: .controlBackgroundColor).opacity(0.36)),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func tabButton(_ tab: PanelTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            Label(tab.title, systemImage: tab.systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor.opacity(0.16))
                    .stroke(Color.accentColor.opacity(0.32), lineWidth: 1)
            }
        }
        .help(tab.title)
    }

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
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
    }

    private var chatPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 42)

            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 64)
                .glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.12)),
                    in: Circle()
                )

            VStack(spacing: 6) {
                Text("AI Chat")
                    .font(.headline)

                Text("Coming soon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            HStack(spacing: 10) {
                Text("Ask Commit+")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.primary.opacity(0.085))
                    .stroke(.primary.opacity(0.12), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .disabled(true)
        }
        .frame(maxWidth: .infinity)
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
            .frame(width: 44, height: 32)
            .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            .background(
                controlBackground(
                    cornerRadius: 10,
                    isProminent: isPinned
                )
            )
            .disabled(!isPinned && pinLimitReached)
            .help(isPinned ? "Unpin from Toolbar" : pinLimitReached ? "Unpin another shortcut first" : "Pin to Toolbar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.primary.opacity(0.075))
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        }
    }

    private func controlBackground(
        cornerRadius: CGFloat,
        isProminent: Bool = false
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(isProminent ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.075))
            .stroke(
                isProminent ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.1),
                lineWidth: 1
            )
    }

    private enum PanelTab: String, CaseIterable, Identifiable {
        case shortcuts
        case chat

        var id: Self { self }

        var title: String {
            switch self {
            case .shortcuts: "Shortcuts"
            case .chat: "Chat"
            }
        }

        var systemImage: String {
            switch self {
            case .shortcuts: "square.grid.2x2"
            case .chat: "bubble.left.and.bubble.right"
            }
        }
    }
}
