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

struct SidebarSubmodulesSection: View {
    let repositoryURL: URL
    let entries: [GitSubmoduleEntry]
    let isExpanded: Bool
    let isLoading: Bool
    let onAddSubmodule: () -> Void
    let actions: SidebarSubmoduleSectionActions

    var body: some View {
        Section {
            headerRow

            if isExpanded {
                if isLoading && entries.isEmpty {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                } else if entries.isEmpty {
                    Text("No submodules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        row(for: entry)
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        SidebarSectionHeader(
            section: .submodules,
            isExpanded: isExpanded,
            activeDropLabel: nil,
            onToggle: actions.toggleSection
        ) {
            Button("Add Submodule", systemImage: "plus", action: onAddSubmodule)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Add Submodule")
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(for entry: GitSubmoduleEntry) -> some View {
        let path = repositoryURL.appendingPathComponent(entry.path, isDirectory: true)
        return SidebarSubmoduleRow(
            entry: entry,
            onOpen: { actions.open(path) },
            onShowInFinder: { actions.showInFinder(path) },
            onOpenInTerminal: { actions.openInTerminal(path) },
            onInitialize: { actions.initialize(entry.path) },
            onUpdateToRecordedCommit: { actions.update(entry.path, .recordedCommit) },
            onUpdateFromRemote: { actions.update(entry.path, .remoteCheckout) },
            onSynchronizeURL: { actions.synchronizeURL(entry.path) },
            onEditSettings: { actions.edit(entry) },
            onDeinitialize: { actions.deinitialize(entry) },
            onRemove: { actions.remove(entry) }
        )
        .tag(SidebarSelection.submodule(entry.path))
    }
}
