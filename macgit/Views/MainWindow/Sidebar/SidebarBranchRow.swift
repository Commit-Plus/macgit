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
import UniformTypeIdentifiers

struct SidebarBranchRow: View {
    let row: BranchRowItem
    let currentBranch: String
    let gitFlowConfiguration: GitFlowConfiguration
    let currentBranchFallbackSyncStatus: BranchSyncStatus?
    let expandedFolders: Set<String>
    let isCurrentBranchDropTargeted: Bool
    let branchSyncStatus: [String: BranchSyncStatus]
    let upstreamByBranch: [String: String]
    let remoteNames: [String]
    let branchesByRemote: [String: [String]]
    let isBranchSyncing: (String) -> Bool
    let deletableBranchesForPrefix: (String) -> [String]
    let makeBranchPayload: (String) -> GitDragPayload
    let finishBranchDrag: (GitDragPayload) -> Void
    let actions: SidebarBranchSectionActions

    var body: some View {
        if row.isFolder {
            content
                .onTapGesture {
                    actions.toggleFolder(row.fullPath)
                }
                .contextMenu {
                    SidebarFolderContextMenu(
                        prefix: row.fullPath,
                        deletableBranches: deletableBranchesForPrefix(row.fullPath),
                        actions: actions
                    )
                }
        } else {
            branchLeafRow
        }
    }

    @ViewBuilder
    private var branchLeafRow: some View {
        let rowView = content
            .tag(SidebarSelection.branch(row.fullPath))
            .onTapGesture {
                actions.select(.branch(row.fullPath))
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if !isCurrentBranch {
                        actions.checkout(row.fullPath)
                    }
                }
            )
            .contextMenu {
                SidebarBranchContextMenu(
                    branch: row.fullPath,
                    currentBranch: currentBranch,
                    syncStatus: branchSyncStatus[row.fullPath],
                    upstream: upstreamByBranch[row.fullPath],
                    remoteNames: remoteNames,
                    branchesByRemote: branchesByRemote,
                    actions: actions
                )
            }
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 8))
            .onDrag {
                actions.makeItemProvider(row.fullPath)
            } preview: {
                BranchDragPreview(branchName: row.fullPath)
            }

        if isCurrentBranch {
            rowView
                .overlay {
                    SidebarBranchDropTarget(
                        onTap: { actions.select(.branch(row.fullPath)) },
                        onTargetedChange: actions.setCurrentDropTargeted,
                        fallbackPayload: actions.drop.activePayload,
                        canAcceptDrop: { payload in
                            actions.drop.canAccept(
                                payload,
                                branchTarget,
                                optionKeyPressed
                            )
                        },
                        dragPayload: { makeBranchPayload(row.fullPath) },
                        dragTitle: { row.fullPath },
                        onDragEnded: finishBranchDrag,
                        onDrop: { payload in
                            actions.drop.handlePayload(payload, branchTarget, optionKeyPressed)
                            return true
                        }
                    )
                }
                .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                    if let payload = actions.drop.activePayload(),
                       !actions.drop.canAccept(payload, branchTarget, optionKeyPressed) {
                        actions.drop.clearPayload(payload)
                        return false
                    }

                    return actions.drop.handleProviders(
                        providers,
                        branchTarget,
                        optionKeyPressed
                    )
                }
        } else {
            rowView
        }
    }

    private var content: BranchRowContent {
        BranchRowContent(
            row: row,
            isCurrentBranch: isCurrentBranch,
            isActiveDropRow: isActiveDropRow,
            dropLabel: isActiveDropRow ? actions.currentDropLabel() : "",
            isBranchSyncing: isBranchSyncing(row.fullPath),
            syncStatus: resolvedSyncStatus,
            headBadgeVisible: isCurrentBranch && !row.isFolder,
            folderIsExpanded: expandedFolders.contains(row.fullPath),
            isCurrentBranchPrefix: isCurrentBranchPrefix,
            gitFlowRole: GitFlowBranchRoleResolver().role(
                for: row.fullPath,
                configuration: gitFlowConfiguration
            )
        )
    }

    private var isCurrentBranch: Bool {
        row.fullPath == currentBranch
    }

    private var isCurrentBranchPrefix: Bool {
        row.isFolder && currentBranch.hasPrefix(row.fullPath + "/")
    }

    private var isActiveDropRow: Bool {
        isCurrentBranch && isCurrentBranchDropTargeted
    }

    private var resolvedSyncStatus: BranchSyncStatus? {
        SidebarBranchSyncBadgeResolver.status(
            for: row.fullPath,
            currentBranch: currentBranch,
            branchSyncStatus: branchSyncStatus,
            currentBranchFallbackSyncStatus: isCurrentBranch ? currentBranchFallbackSyncStatus : nil
        )
    }

    private var branchTarget: GitDragTarget {
        .localBranch(name: row.fullPath, isCurrent: isCurrentBranch)
    }

    private var optionKeyPressed: Bool {
        NSEvent.modifierFlags.contains(.option)
    }
}
