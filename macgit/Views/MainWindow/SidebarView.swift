//
//  SidebarView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

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
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

enum SidebarSelection: Hashable {
    case item(SidebarItem)
    case branch(String)
    case worktree(URL)
    case tag(String)
    case remoteBranch(String)
    case stash(String)
    case head(String)
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case fileStatus = "File status"
    case history = "History"
    case pullRequests = "Pull Requests"
    case search = "Search"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fileStatus: return "doc.text.magnifyingglass"
        case .history: return "clock.arrow.circlepath"
        case .pullRequests: return "arrow.triangle.pull"
        case .search: return "magnifyingglass"
        }
    }
}

enum SidebarSection: String, CaseIterable {
    case workspace = "WORKSPACE"
    case branches = "BRANCHES"
    case worktrees = "WORKTREES"
    case tags = "TAGS"
    case remotes = "REMOTES"
    case stashes = "STASHES"
    case submodules = "SUBMODULES"
    case subtrees = "SUBTREES"

    var items: [SidebarItem] {
        switch self {
        case .workspace:
            return [.fileStatus, .history, .pullRequests, .search]
        default:
            return []
        }
    }
}

struct BranchNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let fullPath: String
    let isFolder: Bool
    var children: [BranchNode]
}

struct BranchRowItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let fullPath: String
    let isFolder: Bool
    let indent: Int
}

enum DeleteConfirmationTarget: Identifiable {
    case single(String)
    case prefix(String)

    var id: String {
        switch self {
        case .single(let branch): return "single:\(branch)"
        case .prefix(let prefix): return "prefix:\(prefix)"
        }
    }
}

struct RemoteBranchDeleteTarget: Identifiable, Equatable {
    let remote: String
    let branch: String

    var id: String { "\(remote)/\(branch)" }
    var fullPath: String { id }
}

enum WorktreeCreationMode: String, CaseIterable {
    case existingBranch = "Existing Branch"
    case newBranch = "New Branch"
}

enum WorktreeHeaderAction: String, CaseIterable {
    case prune = "Prune Worktrees..."
}

enum SidebarBranchSyncBadgeResolver {
    static func status(
        for branch: String,
        currentBranch: String,
        branchSyncStatus: [String: BranchSyncStatus],
        currentBranchFallbackSyncStatus: BranchSyncStatus?
    ) -> BranchSyncStatus? {
        if branch == currentBranch, let currentBranchFallbackSyncStatus {
            return currentBranchFallbackSyncStatus
        }

        return branchSyncStatus[branch]
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appUpdateController: AppUpdateController
    @EnvironmentObject private var appState: AppState

    let repositoryURL: URL
    @Binding var selection: SidebarSelection?
    let undoManager: GitUndoManager?
    let currentBranchFallbackSyncStatus: BranchSyncStatus?
    let isBranchSyncing: (String) -> Bool
    let onRequestCheckout: (String, Bool) -> Void
    let onRequestFetchBranch: (String) -> Void
    let onRequestPullRemoteBranch: (String, String) -> Void
    let onRequestPullTracked: (String) -> Void
    let onRequestPushToTracked: (String) -> Void
    let onRequestRenameBranch: (String) -> Void
    let onRequestCreatePullRequest: (String) -> Void
    let onRequestCreateBranchFromBranch: (String) -> Void
    let onRequestCreateTagFromBranch: (String) -> Void
    let onRequestTagDetails: (String) -> Void
    let onRequestDiffTagAgainstCurrent: (String) -> Void
    let onRequestPushTagToRemote: (String, String) -> Void
    let onRequestDeleteTag: (String) -> Void
    let onRequestRebaseOnto: (String) -> Void
    let onRequestMergeBranchIntoCurrent: (String) -> Void
    let onRequestPushBranchToRemote: (String, String) -> Void
    let onRequestTrackRemoteBranch: (String, String?) -> Void
    let onRequestCreatePullRequestForRemote: (String, String) -> Void
    let onRequestApplyStash: (String) -> Void
    let onRequestDeleteStash: (String) -> Void
    let onRequestOpenWorktree: (URL) -> Void
    let onRequestOpenWorktreeInTerminal: (URL) -> Void
    let onRequestSearch: () -> Void
    let onRequestDragDrop: (GitDragDropRequest) -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State private var branchNodes: [BranchNode] = []
    @State private var currentBranch: String = ""
    @State private var headHash: String = ""
    @State private var branchSyncStatus: [String: BranchSyncStatus] = [:]
    @State private var expandedFolders: Set<String> = []
    @State private var hasLoadedBranches = false
    @State private var isLoadingBranches = false
    @State private var tagNodes: [BranchNode] = []
    @State private var isLoadingTags = false
    @State private var expandedTagFolders: Set<String> = []
    @State private var remoteNodes: [BranchNode] = []
    @State private var remoteNames: [String] = []
    @State private var branchesByRemote: [String: [String]] = [:]
    @State private var upstreamByBranch: [String: String] = [:]
    @State private var isLoadingRemotes = false
    @State private var expandedRemoteFolders: Set<String> = []
    @State private var stashEntries: [StashEntry] = []
    @State private var isLoadingStashes = false
    @State private var worktreeEntries: [WorktreeEntry] = []
    @State private var hasLoadedWorktrees = false
    @State private var isLoadingWorktrees = false
    @State private var worktreeToLabel: WorktreeEntry?
    @State private var worktreeLabelInput = ""
    @State private var worktreeToLock: WorktreeEntry?
    @State private var worktreeLockReasonInput = ""
    @State private var isUpdatingWorktreeLock = false
    @State private var worktreeToMove: WorktreeEntry?
    @State private var worktreeMovePathInput = ""
    @State private var worktreeMoveErrorMessage: String?
    @State private var isMovingWorktree = false
    @State private var worktreeToCheckout: WorktreeEntry?
    @State private var availableWorktreeCheckoutBranches: [String] = []
    @State private var selectedWorktreeCheckoutBranch = ""
    @State private var worktreeCheckoutErrorMessage: String?
    @State private var isCheckingOutWorktreeBranch = false
    @State private var pendingWorktreeForceCheckout: WorktreeEntry?
    @State private var showingWorktreeForceCheckoutConfirmation = false
    @State private var missingWorktreeEntry: WorktreeEntry?
    @State private var showingMissingWorktreeAlert = false
    @State private var pendingWorktreeRemoval: WorktreeEntry?
    @State private var showingWorktreeRemovalConfirmation = false
    @State private var showingPruneWorktreesConfirmation = false
    @State private var createWorktreeMode: WorktreeCreationMode = .existingBranch
    @State private var availableWorktreeBranches: [String] = []
    @State private var currentWorktreeBranch = ""
    @State private var selectedExistingWorktreeBranch = ""
    @State private var newWorktreeBranchName = ""
    @State private var newWorktreeBaseBranch = ""
    @State private var worktreePathInput = ""
    @State private var customWorktreePath = false
    @State private var worktreeLabelDraft = ""
    @State private var openWorktreeAfterCreate = true
    @State private var showingCreateWorktreeSheet = false
    @State private var isCreatingWorktree = false
    @State private var worktreeCreationErrorMessage: String?
    @State private var worktreeRootURL: URL?

    @State private var sectionStates = SidebarSectionState()

    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var deleteConfirmationTarget: DeleteConfirmationTarget?
    @State private var remoteBranchDeleteTarget: RemoteBranchDeleteTarget?
    @State private var forceDeleteBranch = false
    @State private var activeDropTarget: GitDragTarget?
    @State private var activeDropLabel: String?
    @State private var isCurrentBranchDropTargeted = false
    @State private var activeBranchDragPayload: GitDragPayload?

    init(
        repositoryURL: URL,
        selection: Binding<SidebarSelection?>,
        undoManager: GitUndoManager? = nil,
        currentBranchFallbackSyncStatus: BranchSyncStatus? = nil,
        isBranchSyncing: @escaping (String) -> Bool = { _ in false },
        onRequestCheckout: @escaping (String, Bool) -> Void,
        onRequestFetchBranch: @escaping (String) -> Void,
        onRequestPullRemoteBranch: @escaping (String, String) -> Void = { _, _ in },
        onRequestPullTracked: @escaping (String) -> Void = { _ in },
        onRequestPushToTracked: @escaping (String) -> Void = { _ in },
        onRequestRenameBranch: @escaping (String) -> Void = { _ in },
        onRequestCreatePullRequest: @escaping (String) -> Void = { _ in },
        onRequestCreateBranchFromBranch: @escaping (String) -> Void = { _ in },
        onRequestCreateTagFromBranch: @escaping (String) -> Void = { _ in },
        onRequestTagDetails: @escaping (String) -> Void = { _ in },
        onRequestDiffTagAgainstCurrent: @escaping (String) -> Void = { _ in },
        onRequestPushTagToRemote: @escaping (String, String) -> Void = { _, _ in },
        onRequestDeleteTag: @escaping (String) -> Void = { _ in },
        onRequestRebaseOnto: @escaping (String) -> Void = { _ in },
        onRequestMergeBranchIntoCurrent: @escaping (String) -> Void = { _ in },
        onRequestPushBranchToRemote: @escaping (String, String) -> Void = { _, _ in },
        onRequestTrackRemoteBranch: @escaping (String, String?) -> Void = { _, _ in },
        onRequestCreatePullRequestForRemote: @escaping (String, String) -> Void = { _, _ in },
        onRequestApplyStash: @escaping (String) -> Void = { _ in },
        onRequestDeleteStash: @escaping (String) -> Void = { _ in },
        onRequestOpenWorktree: @escaping (URL) -> Void = { _ in },
        onRequestOpenWorktreeInTerminal: @escaping (URL) -> Void = { _ in },
        onRequestSearch: @escaping () -> Void = {},
        onRequestDragDrop: @escaping (GitDragDropRequest) -> Void = { _ in },
        onRunRepositoryOperation: @escaping RepositoryOperationRunner = { _, operation in
            Task { await operation() }
        }
    ) {
        self.repositoryURL = repositoryURL
        self._selection = selection
        self.undoManager = undoManager
        self.currentBranchFallbackSyncStatus = currentBranchFallbackSyncStatus
        self.isBranchSyncing = isBranchSyncing
        self.onRequestCheckout = onRequestCheckout
        self.onRequestFetchBranch = onRequestFetchBranch
        self.onRequestPullRemoteBranch = onRequestPullRemoteBranch
        self.onRequestPullTracked = onRequestPullTracked
        self.onRequestPushToTracked = onRequestPushToTracked
        self.onRequestRenameBranch = onRequestRenameBranch
        self.onRequestCreatePullRequest = onRequestCreatePullRequest
        self.onRequestCreateBranchFromBranch = onRequestCreateBranchFromBranch
        self.onRequestCreateTagFromBranch = onRequestCreateTagFromBranch
        self.onRequestTagDetails = onRequestTagDetails
        self.onRequestDiffTagAgainstCurrent = onRequestDiffTagAgainstCurrent
        self.onRequestPushTagToRemote = onRequestPushTagToRemote
        self.onRequestDeleteTag = onRequestDeleteTag
        self.onRequestRebaseOnto = onRequestRebaseOnto
        self.onRequestMergeBranchIntoCurrent = onRequestMergeBranchIntoCurrent
        self.onRequestPushBranchToRemote = onRequestPushBranchToRemote
        self.onRequestTrackRemoteBranch = onRequestTrackRemoteBranch
        self.onRequestCreatePullRequestForRemote = onRequestCreatePullRequestForRemote
        self.onRequestApplyStash = onRequestApplyStash
        self.onRequestDeleteStash = onRequestDeleteStash
        self.onRequestOpenWorktree = onRequestOpenWorktree
        self.onRequestOpenWorktreeInTerminal = onRequestOpenWorktreeInTerminal
        self.onRequestSearch = onRequestSearch
        self.onRequestDragDrop = onRequestDragDrop
        self.onRunRepositoryOperation = onRunRepositoryOperation
    }

    var body: some View {
        VStack(spacing: 0) {
            if let model = UpdateBannerView.Model.make(for: appUpdateController.state) {
                UpdateBannerView(model: model) {
                    appUpdateController.openUpdateWindow()
                }
            }

            List(selection: $selection) {
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

                Section {
                    branchesSectionHeaderRow

                    if sectionStates.branchesExpanded {
                        if isLoadingBranches && branchNodes.isEmpty {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 4)
                        } else if branchNodes.isEmpty {
                            Text("No branches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            if currentBranch.isEmpty && !headHash.isEmpty {
                                headRowView
                            }

                            ForEach(visibleBranchRows) { row in
                                branchRowView(for: row)
                            }
                        }
                    }
                }

                Section {
                    sectionHeader(.worktrees, isExpanded: sectionStates.worktreesExpanded)

                    if sectionStates.worktreesExpanded {
                        if isLoadingWorktrees && worktreeEntries.isEmpty {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 4)
                        } else if worktreeEntries.isEmpty {
                            Text("No worktrees")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(worktreeEntries) { entry in
                                worktreeRowView(for: entry)
                            }
                        }
                    }
                }

                Section {
                    tagsSectionHeaderRow

                    if sectionStates.tagsExpanded {
                        if isLoadingTags && tagNodes.isEmpty {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 4)
                        } else if tagNodes.isEmpty {
                            Text("No tags")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(visibleTagRows) { row in
                                tagRowView(for: row)
                            }
                        }
                    }
                }

                Section {
                    remotesSectionHeaderRow

                    if sectionStates.remotesExpanded {
                        if isLoadingRemotes && remoteNodes.isEmpty {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 4)
                        } else if remoteNodes.isEmpty {
                            Text("No remotes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(visibleRemoteRows) { row in
                                remoteRowView(for: row)
                            }
                        }
                    }
                }

                Section {
                    stashesSectionHeaderRow

                    if sectionStates.stashesExpanded {
                        if isLoadingStashes && stashEntries.isEmpty {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 4)
                        } else if stashEntries.isEmpty {
                            Text("No stashes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(stashEntries) { stash in
                                stashRowView(for: stash)
                            }
                        }
                    }
                }

                if appState.showSubmodules {
                    Section(SidebarSection.submodules.rawValue) {
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(true)
                }

                if appState.showSubtrees {
                    Section(SidebarSection.subtrees.rawValue) {
                        Text("Coming soon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(true)
                }
            }
            .listStyle(.sidebar)
            .task(id: repositoryURL) {
                loadSectionStates()
                resetLazySectionData()
                await loadVisibleSections(force: false)
                await loadTags()
                await loadRemotes()
                await loadStashes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
                if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                    Task {
                        await loadVisibleSections(force: true)
                        await loadTags()
                        await loadRemotes()
                        await loadStashes()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(item: $deleteConfirmationTarget) { target in
                switch target {
                case .single(let branch):
                    deleteBranchConfirmationSheet(for: branch)
                case .prefix(let prefix):
                    deletePrefixConfirmationSheet(for: prefix)
                }
            }
            .alert("Delete Remote Branch", isPresented: Binding(
                get: { remoteBranchDeleteTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        remoteBranchDeleteTarget = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let target = remoteBranchDeleteTarget {
                        onRunRepositoryOperation("Deleting \(target.fullPath)...") {
                            await deleteRemoteBranch(target)
                        }
                    }
                }
            } message: {
                Text("Delete '\(remoteBranchDeleteTarget?.fullPath ?? "")' from the remote?")
            }
            .alert("Remove Worktree", isPresented: $showingWorktreeRemovalConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button(worktreeRemovalNeedsForce ? "Force Remove" : "Remove", role: .destructive) {
                    if let entry = pendingWorktreeRemoval {
                        onRunRepositoryOperation("Removing \(entry.displayTitle)...") {
                            await removeWorktree(entry, force: worktreeRemovalNeedsForce)
                        }
                    }
                }
            } message: {
                Text(worktreeRemovalMessage)
            }
            .alert("Worktree Moved or Deleted", isPresented: $showingMissingWorktreeAlert, presenting: missingWorktreeEntry) { entry in
                Button("Delete", role: .destructive) {
                    onRunRepositoryOperation("Removing missing worktree...") {
                        await deleteMissingWorktree(entry)
                    }
                }

                Button("Change folder") {
                    chooseReplacementWorktreeFolder(for: entry)
                }

                Button("Cancel", role: .cancel) {
                    missingWorktreeEntry = nil
                }
            } message: { entry in
                Text("\"\(entry.displayTitle)\" is no longer available at \(entry.path.path).")
            }
            .alert("Force Switch Branch", isPresented: $showingWorktreeForceCheckoutConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingWorktreeForceCheckout = nil
                }
                Button("Force Switch", role: .destructive) {
                    if let entry = pendingWorktreeForceCheckout {
                        onRunRepositoryOperation("Switching \(entry.displayTitle)...") {
                            await checkoutWorktree(entry, force: true)
                        }
                    }
                }
            } message: {
                Text("This worktree has uncommitted changes. Force checkout and discard conflicting changes?")
            }
            .alert("Prune Worktrees", isPresented: $showingPruneWorktreesConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Prune", role: .destructive) {
                    onRunRepositoryOperation("Pruning worktrees...") {
                        await pruneWorktrees()
                    }
                }
            } message: {
                Text("Remove stale worktree metadata and orphaned labels for paths that no longer exist?")
            }
            .sheet(item: $worktreeToLabel) { _ in
                worktreeLabelSheet
            }
            .sheet(item: $worktreeToLock) { _ in
                worktreeLockSheet
            }
            .sheet(item: $worktreeToMove) { _ in
                worktreeMoveSheet
            }
            .sheet(item: $worktreeToCheckout) { _ in
                worktreeCheckoutSheet
            }
            .sheet(isPresented: $showingCreateWorktreeSheet) {
                createWorktreeSheet
            }
        }
    }

    // Use a real list row for the branches title because List section headers are unreliable drop targets on macOS.
    private var branchesSectionHeaderRow: some View {
        Group {
            if let remoteBranch = draggedRemoteBranch {
                RemoteBranchCheckoutDropZone(
                    remoteBranch: remoteBranch,
                    isTargeted: activeDropTarget == .branchesHeader
                )
            } else {
                sectionHeaderContent(.branches, isExpanded: sectionStates.branchesExpanded)
            }
        }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                draggedRemoteBranch == nil && activeDropTarget == .branchesHeader
                    ? Color.accentColor.opacity(0.12)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                SidebarBranchDropTarget(
                    onTap: { toggleSection(.branches) },
                    onTargetedChange: updateBranchesHeaderDropTarget,
                    fallbackPayload: { activeBranchDragPayload ?? GitDragPayloadStore.currentPayload() },
                    canAcceptDrop: { payload in
                        canAcceptDrop(
                            payload,
                            target: .branchesHeader,
                            optionKeyPressed: false
                        )
                    },
                    dragPayload: { nil },
                    dragTitle: { "" },
                    onDragEnded: { _ in },
                    onDrop: { payload in
                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear(ifMatching: payload)
                        handleDrop([payload], target: .branchesHeader)
                        return true
                    }
                )
                .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                    if let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload(),
                       !canAcceptDrop(
                           payload,
                           target: .branchesHeader,
                           optionKeyPressed: false
                       ) {
                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear(ifMatching: payload)
                        clearDropHover()
                        return false
                    }
                    activeBranchDragPayload = nil
                    GitDragPayloadStore.clear()
                    return handleDrop(providers, target: .branchesHeader)
                }
            }
    }

    private var tagsSectionHeaderRow: some View {
        sectionHeaderContent(.tags, isExpanded: sectionStates.tagsExpanded)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(activeDropTarget == .tagsHeader ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                SidebarBranchDropTarget(
                    onTap: { toggleSection(.tags) },
                    onTargetedChange: updateTagsHeaderDropTarget,
                    fallbackPayload: { activeBranchDragPayload ?? GitDragPayloadStore.currentPayload() },
                    canAcceptDrop: { payload in
                        canAcceptDrop(
                            payload,
                            target: .tagsHeader,
                            optionKeyPressed: false
                        )
                    },
                    dragPayload: { nil },
                    dragTitle: { "" },
                    onDragEnded: { _ in },
                    onDrop: { payload in
                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear(ifMatching: payload)
                        handleDrop([payload], target: .tagsHeader)
                        return true
                    }
                )
                .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                    if let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload(),
                       !canAcceptDrop(
                           payload,
                           target: .tagsHeader,
                           optionKeyPressed: false
                       ) {
                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear(ifMatching: payload)
                        clearDropHover()
                        return false
                    }
                    activeBranchDragPayload = nil
                    GitDragPayloadStore.clear()
                    return handleDrop(providers, target: .tagsHeader)
                }
            }
    }

    private var remotesSectionHeaderRow: some View {
        sectionHeaderContent(.remotes, isExpanded: sectionStates.remotesExpanded)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(activeDropTarget == .remotesHeader ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                SidebarBranchDropTarget(
                    onTap: { toggleSection(.remotes) },
                    onTargetedChange: updateRemotesHeaderDropTarget,
                    fallbackPayload: { activeBranchDragPayload ?? GitDragPayloadStore.currentPayload() },
                    canAcceptDrop: { payload in
                        canAcceptDrop(
                            payload,
                            target: .remotesHeader,
                            optionKeyPressed: false
                        )
                    },
                    dragPayload: { nil },
                    dragTitle: { "" },
                    onDragEnded: { _ in },
                    onDrop: { payload in
                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear(ifMatching: payload)
                        handleDrop([payload], target: .remotesHeader)
                        return true
                    }
                )
                .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                    if let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload(),
                       !canAcceptDrop(
                           payload,
                           target: .remotesHeader,
                           optionKeyPressed: false
                       ) {
                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear(ifMatching: payload)
                        clearDropHover()
                        return false
                    }
                    activeBranchDragPayload = nil
                    GitDragPayloadStore.clear()
                    return handleDrop(providers, target: .remotesHeader)
                }
            }
    }

    private var stashesSectionHeaderRow: some View {
        sectionHeaderContent(.stashes, isExpanded: sectionStates.stashesExpanded)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(activeDropTarget == .stashesHeader ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                SidebarBranchDropTarget(
                    onTap: { toggleSection(.stashes) },
                    onTargetedChange: updateStashesHeaderDropTarget,
                    fallbackPayload: { activeBranchDragPayload ?? GitDragPayloadStore.currentPayload() },
                    canAcceptDrop: { payload in
                        canAcceptDrop(
                            payload,
                            target: .stashesHeader,
                            optionKeyPressed: false
                        )
                    },
                    dragPayload: { nil },
                    dragTitle: { "" },
                    onDragEnded: { _ in },
                    onDrop: { payload in
                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear(ifMatching: payload)
                        handleDrop([payload], target: .stashesHeader)
                        return true
                    }
                )
                .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                    if let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload(),
                       !canAcceptDrop(
                           payload,
                           target: .stashesHeader,
                           optionKeyPressed: false
                       ) {
                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear(ifMatching: payload)
                        clearDropHover()
                        return false
                    }
                    activeBranchDragPayload = nil
                    GitDragPayloadStore.clear()
                    return handleDrop(providers, target: .stashesHeader)
                }
            }
    }

    @ViewBuilder
    private func sectionHeader(_ section: SidebarSection, isExpanded: Bool) -> some View {
        sectionHeaderContent(section, isExpanded: isExpanded)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sectionHeaderContent(_ section: SidebarSection, isExpanded: Bool) -> some View {
        let isDropActive = (section == .branches && activeDropTarget == .branchesHeader)
            || (section == .tags && activeDropTarget == .tagsHeader)
            || (section == .remotes && activeDropTarget == .remotesHeader)
            || (section == .stashes && activeDropTarget == .stashesHeader)

        HStack {
            Text(section.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if isDropActive, let activeDropLabel {
                Text(activeDropLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            if section == .worktrees {
                Button("Create Worktree", systemImage: "plus") {
                    onRunRepositoryOperation("Preparing worktree creation...") {
                        await prepareCreateWorktreeSheet()
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Create Worktree")

                Menu {
                    Button(WorktreeHeaderAction.prune.rawValue) {
                        showingPruneWorktreesConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .tint(Color(nsColor: .secondaryLabelColor))
                .fixedSize()
                .help("Worktree Actions")
            }
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSection(section)
        }
    }

    private func loadSectionStates() {
        var state = SidebarSettingsStore.shared.state(for: repositoryURL.path)
        state.branchesExpanded = false
        state.worktreesExpanded = false
        SidebarSettingsStore.shared.update(for: repositoryURL.path, state: state)
        sectionStates = state
    }

    private func toggleSection(_ section: SidebarSection) {
        SidebarSettingsStore.shared.toggleSection(section, for: repositoryURL.path)
        sectionStates = SidebarSettingsStore.shared.state(for: repositoryURL.path)
        Task {
            await loadSectionIfNeeded(section)
        }
    }

    private func updateBranchesHeaderDropTarget(isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .branchesHeader
            activeDropLabel = draggedRemoteBranch == nil ? "Create Branch" : "Check Out"
        } else if activeDropTarget == .branchesHeader {
            clearDropHover()
        }
    }

    private func updateTagsHeaderDropTarget(isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .tagsHeader
            activeDropLabel = "Create Tag"
        } else if activeDropTarget == .tagsHeader {
            clearDropHover()
        }
    }

    private func updateRemotesHeaderDropTarget(isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .remotesHeader
            activeDropLabel = "Push Branch"
        } else if activeDropTarget == .remotesHeader {
            clearDropHover()
        }
    }

    private func updateStashesHeaderDropTarget(isTargeted: Bool) {
        if isTargeted {
            activeDropTarget = .stashesHeader
            let fileCount = currentFileDragCount()
            activeDropLabel = fileCount > 1 ? "Stash \(fileCount) files" : "Stash"
        } else if activeDropTarget == .stashesHeader {
            clearDropHover()
        }
    }

    private func currentFileDragCount() -> Int {
        if let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload(),
           !payload.files.isEmpty {
            return payload.files.count
        }
        return 0
    }

    private func updateCurrentBranchDropTarget(isTargeted: Bool) {
        isCurrentBranchDropTargeted = isTargeted
    }

    private func makeBranchItemProvider(branchName: String) -> NSItemProvider {
        let payload = makeBranchPayload(branchName: branchName)

        let provider = NSItemProvider()
        if let data = try? GitDragPayload.encodeTransferData(payload) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.macgitGitDragPayload.identifier,
                visibility: .all
            ) { completionHandler in
                completionHandler(data, nil)
                return nil
            }
        }
        provider.register(payload)
        provider.suggestedName = branchName
        return provider
    }

    private func makeBranchPayload(branchName: String) -> GitDragPayload {
        let payload = GitDragPayload.branch(
            branchName,
            repositoryURL: repositoryURL
        )
        activeBranchDragPayload = payload
        GitDragPayloadStore.set(payload)
        return payload
    }

    private func makeRemoteBranchPayload(remoteBranch: String) -> GitDragPayload {
        let payload = GitDragPayload.remoteBranch(remoteBranch, repositoryURL: repositoryURL)
        activeBranchDragPayload = payload
        GitDragPayloadStore.set(payload)
        return payload
    }

    private func makeStashPayload(ref: String) -> GitDragPayload {
        let payload = GitDragPayload.stash(ref, repositoryURL: repositoryURL)
        activeBranchDragPayload = payload
        GitDragPayloadStore.set(payload)
        return payload
    }

    private var draggedRemoteBranch: String? {
        let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload()
        return payload?.remoteBranch
    }

    private func finishRemoteBranchDrag(_ remoteBranch: String) {
        guard let payload = activeBranchDragPayload,
              payload.remoteBranch == remoteBranch
        else {
            return
        }
        activeBranchDragPayload = nil
        GitDragPayloadStore.clear(ifMatching: payload)
        clearDropHover()
    }

    private func clearDropHover() {
        activeDropTarget = nil
        activeDropLabel = nil
    }

    private func canAcceptDrop(
        _ payload: GitDragPayload,
        target: GitDragTarget,
        optionKeyPressed: Bool = false
    ) -> Bool {
        if case .accept = GitDragDropPolicy.decision(
            for: payload,
            target: target,
            receivingRepositoryURL: repositoryURL,
            optionKeyPressed: optionKeyPressed
        ) {
            return true
        }

        return false
    }

    private func handleDrop(
        _ items: [GitDragPayload],
        target: GitDragTarget,
        optionKeyPressed: Bool = false
    ) {
        defer { clearDropHover() }

        guard let payload = items.first else { return }

        switch GitDragDropPolicy.decision(
            for: payload,
            target: target,
            receivingRepositoryURL: repositoryURL,
            optionKeyPressed: optionKeyPressed
        ) {
        case .accept(let request):
            if case .checkoutRemoteBranch = request {
                expandBranchesSection()
            }
            onRequestDragDrop(request)
        case .reject(let reason):
            guard payload.remoteBranch == nil else { return }
            errorMessage = reason
            showingError = true
        }
    }

    private func handleDrop(
        _ providers: [NSItemProvider],
        target: GitDragTarget,
        optionKeyPressed: Bool = false
    ) -> Bool {
        guard let provider = providers.first else { return false }

        GitDragPayloadItemProviderLoader.load(from: provider) { result in
            Task { @MainActor in
                switch result {
                case .success(let payload):
                    handleDrop(
                        [payload],
                        target: target,
                        optionKeyPressed: optionKeyPressed
                    )
                case .failure(let error):
                    clearDropHover()
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }

        return true
    }

    private func resetLazySectionData() {
        branchNodes = []
        currentBranch = ""
        headHash = ""
        branchSyncStatus = [:]
        expandedFolders = []
        hasLoadedBranches = false
        isLoadingBranches = false

        worktreeEntries = []
        hasLoadedWorktrees = false
        isLoadingWorktrees = false
    }

    private func loadVisibleSections(force: Bool) async {
        if sectionStates.branchesExpanded {
            await loadBranches(force: force)
        }
        if sectionStates.worktreesExpanded {
            await loadWorktrees(force: force)
        }
    }

    private func loadSectionIfNeeded(_ section: SidebarSection) async {
        switch section {
        case .branches:
            if sectionStates.branchesExpanded {
                await loadBranches(force: false)
            }
        case .worktrees:
            if sectionStates.worktreesExpanded {
                await loadWorktrees(force: false)
            }
        default:
            break
        }
    }

    private var visibleBranchRows: [BranchRowItem] {
        SidebarTreeBuilder.visibleRows(from: branchNodes, expandedFolders: expandedFolders)
    }

    private var visibleTagRows: [BranchRowItem] {
        SidebarTreeBuilder.visibleRows(from: tagNodes, expandedFolders: expandedTagFolders)
    }

    private var visibleRemoteRows: [BranchRowItem] {
        SidebarTreeBuilder.visibleRows(from: remoteNodes, expandedFolders: expandedRemoteFolders)
    }

    private var canCreateWorktree: Bool {
        let trimmedPath = worktreePathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }

        switch createWorktreeMode {
        case .existingBranch:
            return !selectedExistingWorktreeBranch.isEmpty
        case .newBranch:
            return !sanitizedWorktreeBranchName(newWorktreeBranchName).isEmpty
        }
    }

    private var canMoveWorktree: Bool {
        guard let entry = worktreeToMove else { return false }
        let trimmedPath = worktreeMovePathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }

        let candidate = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
        return candidate != entry.path.standardizedFileURL.path
    }

    private var canCheckoutWorktreeBranch: Bool {
        !selectedWorktreeCheckoutBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var worktreeRemovalNeedsForce: Bool {
        guard let entry = pendingWorktreeRemoval else { return false }
        return entry.dirtyCount > 0 || entry.isLocked
    }

    private var worktreeRemovalMessage: String {
        guard let entry = pendingWorktreeRemoval else {
            return "Are you sure you want to remove this worktree?"
        }

        if entry.isLocked && entry.dirtyCount > 0 {
            return "This worktree is locked and has \(entry.dirtyCount) uncommitted changes. Remove it with --force?"
        }

        if entry.isLocked {
            return "This worktree is locked. Remove it with --force?"
        }

        if entry.dirtyCount > 0 {
            return "This worktree has \(entry.dirtyCount) uncommitted changes. Remove it with --force?"
        }

        return "Remove this worktree? The branch and commits are not deleted."
    }

    @ViewBuilder
    private var headRowView: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: 16)
            }

            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16, alignment: .center)

            Text("HEAD")
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)

            if !headHash.isEmpty {
                Text(headHash)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .tag(SidebarSelection.head(headHash))
        .onTapGesture {
            selection = .head(headHash)
        }
    }

    @ViewBuilder
    private func branchRowView(for row: BranchRowItem) -> some View {
        let isCurrentBranch = row.fullPath == currentBranch
        let branchTarget = GitDragTarget.localBranch(
            name: row.fullPath,
            isCurrent: isCurrentBranch
        )
        let isActiveDropRow = isCurrentBranch && isCurrentBranchDropTargeted
        let headBadgeVisible = isCurrentBranch && !row.isFolder
        let resolvedSyncStatus = SidebarBranchSyncBadgeResolver.status(
            for: row.fullPath,
            currentBranch: currentBranch,
            branchSyncStatus: branchSyncStatus,
            currentBranchFallbackSyncStatus: isCurrentBranch ? currentBranchFallbackSyncStatus : nil
        )

        let content = BranchRowContent(
            row: row,
            isCurrentBranch: isCurrentBranch,
            isActiveDropRow: isActiveDropRow,
            dropLabel: isActiveDropRow ? currentBranchDropLabel() : "",
            isBranchSyncing: isBranchSyncing(row.fullPath),
            syncStatus: resolvedSyncStatus,
            headBadgeVisible: headBadgeVisible,
            folderIsExpanded: expandedFolders.contains(row.fullPath)
        )

        if row.isFolder {
            content
                .onTapGesture {
                    toggleFolder(row.fullPath)
                }
                .contextMenu {
                    folderContextMenu(for: row.fullPath)
                }
        } else {
            let rowView = content
                .tag(SidebarSelection.branch(row.fullPath))
                .onTapGesture {
                    selection = .branch(row.fullPath)
                }
                .onTapGesture(count: 2) {
                    if !isCurrentBranch {
                        onRequestCheckout(row.fullPath, false)
                    }
                }
                .contextMenu {
                    branchContextMenu(for: row.fullPath)
                }
                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 8))
                .onDrag {
                    makeBranchItemProvider(branchName: row.fullPath)
                } preview: {
                    BranchDragPreview(branchName: row.fullPath)
                }

        if isCurrentBranch {
                rowView
                    .overlay {
                        SidebarBranchDropTarget(
                            onTap: { selection = .branch(row.fullPath) },
                            onTargetedChange: updateCurrentBranchDropTarget,
                            fallbackPayload: { activeBranchDragPayload ?? GitDragPayloadStore.currentPayload() },
                            canAcceptDrop: { payload in
                                canAcceptDrop(
                                    payload,
                                    target: branchTarget,
                                    optionKeyPressed: NSEvent.modifierFlags.contains(.option)
                                )
                            },
                            dragPayload: { makeBranchPayload(branchName: row.fullPath) },
                            dragTitle: { row.fullPath },
                            onDragEnded: { payload in
                                activeBranchDragPayload = nil
                                GitDragPayloadStore.clear(ifMatching: payload)
                            },
                            onDrop: { payload in
                                activeBranchDragPayload = nil
                                GitDragPayloadStore.clear(ifMatching: payload)
                                handleDrop(
                                    [payload],
                                    target: branchTarget,
                                    optionKeyPressed: NSEvent.modifierFlags.contains(.option)
                                )
                                return true
                            }
                        )
                    }
                    .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                        let optionKeyPressed = NSEvent.modifierFlags.contains(.option)
                        if let payload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload(),
                           !canAcceptDrop(
                               payload,
                               target: branchTarget,
                               optionKeyPressed: optionKeyPressed
                           ) {
                            activeBranchDragPayload = nil
                            GitDragPayloadStore.clear(ifMatching: payload)
                            clearDropHover()
                            return false
                        }

                        activeBranchDragPayload = nil
                        GitDragPayloadStore.clear()
                        return handleDrop(
                            providers,
                            target: branchTarget,
                            optionKeyPressed: optionKeyPressed
                        )
                    }
            } else {
                rowView
            }
        }
    }

    private func currentBranchDropLabel() -> String {
        let activePayload = activeBranchDragPayload ?? GitDragPayloadStore.currentPayload()
        if case .commits = activePayload?.content {
            return "Cherry-pick"
        }
        if case .branch = activePayload?.content {
            return NSEvent.modifierFlags.contains(.option) ? "Rebase" : "Merge"
        }

        if NSEvent.modifierFlags.contains(.option) {
            return "Rebase or Cherry-pick"
        }
        return "Merge or Cherry-pick"
    }

    @ViewBuilder
    private func worktreeRowView(for entry: WorktreeEntry) -> some View {
        let isMain = isCurrentRepositoryWorktree(entry)
        let baseView = HStack(spacing: 4) {
            Image(systemName: entry.isLocked ? "lock.fill" : (isMain ? "circle.fill" : "folder"))
                .font(.system(size: isMain ? 7 : 10))
                .foregroundStyle(isMain ? Color.accentColor : .secondary)
                .frame(width: 16, alignment: .center)

            Text(entry.displayTitle)
                .font(.system(size: 12))
                .fontWeight(isMain ? .bold : .regular)
                .italic(isMain)
                .lineLimit(1)

            if isMain {
                Text("(this)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isMain, entry.dirtyCount > 0 {
                Text("\(entry.dirtyCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .cornerRadius(4)
            } else if !isMain, entry.dirtyCount < 0 {
                Text("?")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())

        baseView
            .tag(SidebarSelection.worktree(entry.path))
            .onTapGesture {
                selectWorktree(entry)
            }
            .onTapGesture(count: 2) {
                openWorktree(entry)
            }
            .contextMenu {
                worktreeContextMenu(for: entry)
            }
    }

    @ViewBuilder
    private func tagRowView(for row: BranchRowItem) -> some View {
        let baseView = HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16)
                }
            }

            if row.isFolder {
                Image(systemName: expandedTagFolders.contains(row.fullPath) ? "chevron.down" : "chevron.right")
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

        if row.isFolder {
            baseView
                .onTapGesture {
                    toggleTagFolder(row.fullPath)
                }
        } else {
            baseView
                .tag(SidebarSelection.tag(row.fullPath))
                .onTapGesture {
                    selection = .tag(row.fullPath)
                }
                .onTapGesture(count: 2) {
                    onRequestCheckout(row.fullPath, true)
                }
                .contextMenu {
                    tagContextMenu(for: row.fullPath)
                }
        }
    }

    @ViewBuilder
    private func tagContextMenu(for tag: String) -> some View {
        Button("Copy Tag Name to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tag, forType: .string)
        }

        Divider()

        Button("Checkout \(tag)") {
            onRequestCheckout(tag, true)
        }
        Button("Details...") {
            onRequestTagDetails(tag)
        }

        Divider()

        Button("Diff Against Current") {
            onRequestDiffTagAgainstCurrent(tag)
        }

        Divider()

        Menu("Push to") {
            if remoteNames.isEmpty {
                Text("No remotes configured")
            } else {
                ForEach(remoteNames.sorted(), id: \.self) { remote in
                    Button(remote) {
                        onRequestPushTagToRemote(tag, remote)
                    }
                }
            }
        }
        .disabled(remoteNames.isEmpty)

        Button("Delete \(tag)", role: .destructive) {
            onRequestDeleteTag(tag)
        }
    }

    @ViewBuilder
    private func remoteRowView(for row: BranchRowItem) -> some View {
        let baseView = HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16)
                }
            }

            if row.isFolder {
                Image(systemName: expandedRemoteFolders.contains(row.fullPath) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            } else {
                Color.clear
                    .frame(width: 16)
            }

            Text(row.name)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())

        if row.isFolder {
            baseView
                .onTapGesture {
                    toggleRemoteFolder(row.fullPath)
                }
        } else {
            let rowView = baseView
                .tag(SidebarSelection.remoteBranch(row.fullPath))
                .onTapGesture {
                    selection = .remoteBranch(row.fullPath)
                }
                .onTapGesture(count: 2) {
                    selection = .remoteBranch(row.fullPath)
                    Task {
                        await checkoutRemoteBranch(row.fullPath)
                    }
                }

            if remoteBranchParts(from: row.fullPath)?.branch == "HEAD" {
                rowView
                    .contextMenu {
                        remoteBranchContextMenu(for: row.fullPath)
                    }
            } else {
                rowView
                    .overlay {
                        SidebarRemoteBranchDragSource(
                            onTap: {
                                selection = .remoteBranch(row.fullPath)
                            },
                            onDoubleTap: {
                                selection = .remoteBranch(row.fullPath)
                                Task {
                                    await checkoutRemoteBranch(row.fullPath)
                                }
                            },
                            dragPayload: {
                                makeRemoteBranchPayload(remoteBranch: row.fullPath)
                            },
                            dragTitle: row.fullPath,
                            onDragEnded: {
                                finishRemoteBranchDrag(row.fullPath)
                            }
                        )
                    }
                    .contextMenu {
                        remoteBranchContextMenu(for: row.fullPath)
                    }
            }
        }
    }

    @ViewBuilder
    private func stashRowView(for stash: StashEntry) -> some View {
        let baseView = HStack(spacing: 4) {
            Image(systemName: "tray")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            Text(stash.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())

        baseView
            .tag(SidebarSelection.stash(stash.ref))
            .onTapGesture {
                selection = .stash(stash.ref)
            }
            .onTapGesture(count: 2) {
                onRequestApplyStash(stash.ref)
            }
            .onDrag {
                makeStashItemProvider(ref: stash.ref)
            } preview: {
                StashDragPreview(title: stash.displayTitle)
            }
            .contextMenu {
                Button("Apply stash") {
                    onRequestApplyStash(stash.ref)
                }
                Button("Delete stash", role: .destructive) {
                    onRequestDeleteStash(stash.ref)
                }
            }
    }

    private func makeStashItemProvider(ref: String) -> NSItemProvider {
        let payload = makeStashPayload(ref: ref)

        let provider = NSItemProvider()
        if let data = try? GitDragPayload.encodeTransferData(payload) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.macgitGitDragPayload.identifier,
                visibility: .all
            ) { completionHandler in
                completionHandler(data, nil)
                return nil
            }
        }
        provider.register(payload)
        provider.suggestedName = ref
        return provider
    }

    private func toggleFolder(_ path: String) {
        if expandedFolders.contains(path) {
            expandedFolders.remove(path)
        } else {
            expandedFolders.insert(path)
        }
    }

    private func toggleTagFolder(_ path: String) {
        if expandedTagFolders.contains(path) {
            expandedTagFolders.remove(path)
        } else {
            expandedTagFolders.insert(path)
        }
    }

    private func toggleRemoteFolder(_ path: String) {
        if expandedRemoteFolders.contains(path) {
            expandedRemoteFolders.remove(path)
        } else {
            expandedRemoteFolders.insert(path)
        }
    }

    @ViewBuilder
    private func remoteBranchContextMenu(for fullPath: String) -> some View {
        if let remoteBranch = remoteBranchParts(from: fullPath) {
            Button("Checkout...") {
                selection = .remoteBranch(fullPath)
                onRunRepositoryOperation("Checking out \(fullPath)...") {
                    await checkoutRemoteBranch(fullPath)
                }
            }
            .disabled(remoteBranch.branch == "HEAD")

            let pullTarget = currentBranch.isEmpty ? "current branch" : currentBranch
            Button("Pull \(fullPath) into \(pullTarget)") {
                onRequestPullRemoteBranch(remoteBranch.remote, remoteBranch.branch)
            }
            .disabled(currentBranch.isEmpty || remoteBranch.branch == "HEAD")

            Divider()

            Button("Copy Branch Name to Clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullPath, forType: .string)
            }

            Button("Diff Against Current") {}
                .disabled(true)

            Divider()

            Button("Delete...", role: .destructive) {
                remoteBranchDeleteTarget = RemoteBranchDeleteTarget(
                    remote: remoteBranch.remote,
                    branch: remoteBranch.branch
                )
            }
            .disabled(remoteBranch.branch == "HEAD")

            Divider()

            Button("Create Pull Request...") {
                onRequestCreatePullRequestForRemote(remoteBranch.remote, remoteBranch.branch)
            }
            .disabled(remoteBranch.branch == "HEAD")
        } else {
            Button("Copy Branch Name to Clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullPath, forType: .string)
            }
        }
    }

    private func checkoutRemoteBranch(_ fullPath: String) async {
        guard let remoteBranch = remoteBranchParts(from: fullPath) else {
            await MainActor.run {
                errorMessage = "Could not parse remote branch '\(fullPath)'."
                showingError = true
            }
            return
        }

        do {
            let localBranch = try await GitStatusService.shared.checkoutRemoteBranch(
                remote: remoteBranch.remote,
                branch: remoteBranch.branch,
                in: repositoryURL
            )
            expandBranchesSection()
            await loadBranches(force: true)
            await loadRemotes()
            await MainActor.run {
                selection = .branch(localBranch)
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func deleteRemoteBranch(_ target: RemoteBranchDeleteTarget) async {
        do {
            _ = try await GitStatusService.shared.deleteRemoteBranch(
                remote: target.remote,
                name: target.branch,
                in: repositoryURL
            )
            await loadRemotes()
            await MainActor.run {
                remoteBranchDeleteTarget = nil
                if selection == .remoteBranch(target.fullPath) {
                    selection = .item(.history)
                }
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await MainActor.run {
                remoteBranchDeleteTarget = nil
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    @MainActor
    private func expandBranchesSection() {
        guard !sectionStates.branchesExpanded else { return }
        sectionStates.branchesExpanded = true
        SidebarSettingsStore.shared.update(for: repositoryURL.path, state: sectionStates)
    }

    private func remoteBranchParts(from fullPath: String) -> (remote: String, branch: String)? {
        let parts = fullPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let remote = String(parts[0])
        let branch = String(parts[1])
        guard !remote.isEmpty, !branch.isEmpty else { return nil }
        return (remote, branch)
    }

    @ViewBuilder
    private func branchContextMenu(for branch: String) -> some View {
        Button("Checkout \(branch)") {
            onRequestCheckout(branch, false)
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Merge \(branch) into \(currentBranch)") {
            onRequestMergeBranchIntoCurrent(branch)
        }
        .disabled(branch == currentBranch)
        Button("Rebase current changes onto \(branch)") {
            onRequestRebaseOnto(branch)
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Fetch \(branch)") {
            onRequestFetchBranch(branch)
        }
        .disabled(!BranchFetchActionPolicy.shouldEnableFetch(for: branchSyncStatus[branch]))
        let currentUpstream = upstreamByBranch[branch]
        let pullLabel = currentUpstream.map { "Pull \($0) (tracked)" } ?? "Pull (tracked)"
        Button(pullLabel) {
            onRequestPullTracked(branch)
        }
        .disabled(!BranchUpstreamActionPolicy.shouldEnablePullFromUpstream(for: currentUpstream))
        let pushLabel = currentUpstream.map { "Push to \($0) (tracked)" } ?? "Push to (tracked)"
        Button(pushLabel) {
            onRequestPushToTracked(branch)
        }
        .disabled(!BranchUpstreamActionPolicy.shouldEnablePushToUpstream(for: currentUpstream))
        Menu("Push to") {
            if remoteNames.isEmpty {
                Text("No remotes configured")
            } else {
                ForEach(remoteNames, id: \.self) { remote in
                    Button(remote) {
                        onRequestPushBranchToRemote(branch, remote)
                    }
                }
            }
        }
        .disabled(remoteNames.isEmpty)
        Menu("Track Remote Branch") {
            if remoteNames.isEmpty {
                Text("No remotes configured")
            } else {
                let currentUpstream = upstreamByBranch[branch]
                let hasAnyRemoteBranch = remoteNames.contains { !(branchesByRemote[$0] ?? []).isEmpty }
                if hasAnyRemoteBranch {
                    ForEach(remoteNames.sorted(), id: \.self) { remote in
                        ForEach((branchesByRemote[remote] ?? []).sorted(), id: \.self) { remoteBranch in
                            let upstreamRef = "\(remote)/\(remoteBranch)"
                            Button {
                                onRequestTrackRemoteBranch(branch, upstreamRef)
                            } label: {
                                if currentUpstream == upstreamRef {
                                    Label(upstreamRef, systemImage: "checkmark")
                                } else {
                                    Text(upstreamRef)
                                }
                            }
                        }
                    }
                    Divider()
                } else {
                    Text("No remote branches")
                    Divider()
                }
                Button {
                    onRequestTrackRemoteBranch(branch, nil)
                } label: {
                    if currentUpstream == nil {
                        Label("(None)", systemImage: "checkmark")
                    } else {
                        Text("(None)")
                    }
                }
            }
        }
        .disabled(remoteNames.isEmpty)

        Divider()

        Button("Create Branch from '\(branch)'...") {
            onRequestCreateBranchFromBranch(branch)
        }
        Button("Create Tag from '\(branch)'...") {
            onRequestCreateTagFromBranch(branch)
        }

        Divider()

        Button("Diff Against Current") {}
            .disabled(true)

        Divider()

        Button("Rename...") {
            onRequestRenameBranch(branch)
        }
        Button("Delete \(branch)") {
            deleteConfirmationTarget = .single(branch)
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Copy Branch Name to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch, forType: .string)
        }

        Divider()

        Button("Create Pull Request...") {
            onRequestCreatePullRequest(branch)
        }
        .disabled(!BranchUpstreamActionPolicy.shouldEnableCreatePullRequest(for: currentUpstream))
    }

    @ViewBuilder
    private func folderContextMenu(for prefix: String) -> some View {
        let deletable = branchesUnderPrefix(prefix).filter { $0 != currentBranch }

        Button("Delete All in \u{201C}\(prefix)/\u{201D}\u{2026}") {
            deleteConfirmationTarget = .prefix(prefix)
        }
        .disabled(deletable.isEmpty)

        Divider()

        Button("Copy Folder Name to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prefix, forType: .string)
        }
    }

    @ViewBuilder
    private func worktreeContextMenu(for entry: WorktreeEntry) -> some View {
        Button("Open in New Window") {
            onRequestOpenWorktree(entry.path)
        }

        Button("Open in Terminal") {
            onRequestOpenWorktreeInTerminal(entry.path)
        }

        Divider()

        Button(entry.label == nil ? "Set Label..." : "Edit Label...") {
            beginEditingWorktreeLabel(entry)
        }

        if entry.label != nil {
            Button("Clear Label") {
                onRunRepositoryOperation("Clearing worktree label...") {
                    await clearWorktreeLabel(entry)
                }
            }
        }

        Divider()

        if !isCurrentRepositoryWorktree(entry) {
            if entry.isLocked {
                Button("Unlock Worktree") {
                    onRunRepositoryOperation("Unlocking \(entry.displayTitle)...") {
                        await unlockWorktree(entry)
                    }
                }
            } else {
                Button("Lock Worktree...") {
                    beginLockingWorktree(entry)
                }
            }

            Button("Rename/Move Worktree...") {
                beginMovingWorktree(entry)
            }

            Button("Switch Branch...") {
                onRunRepositoryOperation("Preparing branch switch...") {
                    await prepareCheckoutWorktreeSheet(for: entry)
                }
            }

            Divider()

            Button("Remove Worktree...", role: .destructive) {
                pendingWorktreeRemoval = entry
                showingWorktreeRemovalConfirmation = true
            }

            Divider()
        }

        Button("Copy Path to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.path.path, forType: .string)
        }
    }

    @ViewBuilder
    private var worktreeLabelSheet: some View {
        if let entry = worktreeToLabel {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.label == nil ? "Set Worktree Label" : "Edit Worktree Label")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Worktree:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(entry.path.path)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Label:")
                        .font(.system(size: 13))
                    TextField(entry.branch ?? entry.path.lastPathComponent, text: $worktreeLabelInput)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        worktreeToLabel = nil
                        worktreeLabelInput = ""
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Save") {
                        onRunRepositoryOperation("Saving worktree label...") {
                            await saveWorktreeLabel()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 420, idealWidth: 480)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var worktreeLockSheet: some View {
        if let entry = worktreeToLock {
            VStack(alignment: .leading, spacing: 16) {
                Text("Lock Worktree")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Worktree:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(entry.path.path)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Reason (optional):")
                        .font(.system(size: 13))
                    TextField("Reason", text: $worktreeLockReasonInput)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        worktreeToLock = nil
                        worktreeLockReasonInput = ""
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isUpdatingWorktreeLock)

                    Button("Lock") {
                        onRunRepositoryOperation("Locking \(entry.displayTitle)...") {
                            await lockWorktree(entry)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isUpdatingWorktreeLock)
                }
            }
            .padding(24)
            .frame(minWidth: 420, idealWidth: 480)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var worktreeMoveSheet: some View {
        if let entry = worktreeToMove {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename/Move Worktree")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current path:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(entry.path.path)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("New path:")
                        .font(.system(size: 13))
                    TextField("", text: $worktreeMovePathInput)
                        .textFieldStyle(.roundedBorder)
                }

                if let worktreeMoveErrorMessage {
                    Text(worktreeMoveErrorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        worktreeToMove = nil
                        worktreeMovePathInput = ""
                        worktreeMoveErrorMessage = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isMovingWorktree)

                    Button("Move") {
                        onRunRepositoryOperation("Moving \(entry.displayTitle)...") {
                            await moveWorktree(entry)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canMoveWorktree || isMovingWorktree)
                }
            }
            .padding(24)
            .frame(minWidth: 460, idealWidth: 520)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func deleteBranchConfirmationSheet(for branch: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Branch")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Are you sure you want to delete the branch '\(branch)'?")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            forceDeleteToggle

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    deleteConfirmationTarget = nil
                    forceDeleteBranch = false
                }
                .keyboardShortcut(.cancelAction)

                Button(forceDeleteBranch ? "Force Delete" : "Delete", role: .destructive) {
                    let force = forceDeleteBranch
                    deleteConfirmationTarget = nil
                    forceDeleteBranch = false
                    onRunRepositoryOperation("Deleting \(branch)...") {
                        await deleteBranch(branch, force: force)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
    }

    @ViewBuilder
    private func deletePrefixConfirmationSheet(for prefix: String) -> some View {
        let all = branchesUnderPrefix(prefix)
        let deletable = all.filter { $0 != currentBranch }
        let skipped = all.filter { $0 == currentBranch }

        VStack(alignment: .leading, spacing: 16) {
            Text("Delete All Branches in \u{201C}\(prefix)/\u{201D}")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This will delete \(deletable.count) branch\(deletable.count == 1 ? "" : "es") with the prefix \u{201C}\(prefix)/\u{201D}.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            if !skipped.isEmpty {
                Text("The current branch \u{201C}\(currentBranch)\u{201D} will be skipped because it is checked out.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(deletable, id: \.self) { branch in
                    Text("\u{2022} \(branch)")
                        .font(.system(size: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            forceDeleteToggle

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    deleteConfirmationTarget = nil
                    forceDeleteBranch = false
                }
                .keyboardShortcut(.cancelAction)

                Button(forceDeleteBranch ? "Force Delete All" : "Delete All", role: .destructive) {
                    let force = forceDeleteBranch
                    deleteConfirmationTarget = nil
                    forceDeleteBranch = false
                    onRunRepositoryOperation("Deleting branches in \(prefix)/...") {
                        await deleteBranchesWithPrefix(prefix, force: force)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(deletable.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
    }

    private var forceDeleteToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Force delete regardless of merge status", isOn: $forceDeleteBranch)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            Text("Use \u{201C}git branch -D\u{201D}. Required for branches that are not fully merged; otherwise their commits may become unreachable.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var worktreeCheckoutSheet: some View {
        if let entry = worktreeToCheckout {
            VStack(alignment: .leading, spacing: 16) {
                Text("Switch Worktree Branch")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Worktree:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(entry.path.path)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch:")
                        .font(.system(size: 13))
                    Picker("", selection: $selectedWorktreeCheckoutBranch) {
                        ForEach(availableWorktreeCheckoutBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let worktreeCheckoutErrorMessage {
                    Text(worktreeCheckoutErrorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        worktreeToCheckout = nil
                        worktreeCheckoutErrorMessage = nil
                        selectedWorktreeCheckoutBranch = ""
                        availableWorktreeCheckoutBranches = []
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCheckingOutWorktreeBranch)

                    Button("Switch") {
                        if entry.dirtyCount > 0 {
                            pendingWorktreeForceCheckout = entry
                            showingWorktreeForceCheckoutConfirmation = true
                        } else {
                            onRunRepositoryOperation("Switching \(entry.displayTitle)...") {
                                await checkoutWorktree(entry, force: false)
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCheckoutWorktreeBranch || isCheckingOutWorktreeBranch)
                }
            }
            .padding(24)
            .frame(minWidth: 420, idealWidth: 480)
        } else {
            EmptyView()
        }
    }

    private var createWorktreeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Worktree")
                .font(.title2)
                .fontWeight(.semibold)

            Picker("", selection: $createWorktreeMode) {
                ForEach(WorktreeCreationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: createWorktreeMode) { _, _ in
                refreshWorktreePathIfNeeded(force: false)
            }

            if createWorktreeMode == .existingBranch {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Branch:")
                        .font(.system(size: 13))
                    Picker("", selection: $selectedExistingWorktreeBranch) {
                        ForEach(availableWorktreeBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedExistingWorktreeBranch) { _, _ in
                        refreshWorktreePathIfNeeded(force: false)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New branch name:")
                        .font(.system(size: 13))
                    TextField("feature/worktree-task", text: $newWorktreeBranchName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: newWorktreeBranchName) { _, _ in
                            refreshWorktreePathIfNeeded(force: false)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Base branch:")
                        .font(.system(size: 13))
                    Picker("", selection: $newWorktreeBaseBranch) {
                        ForEach(availableWorktreeBranches, id: \.self) { branch in
                            Text(branch).tag(branch)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Path:")
                    .font(.system(size: 13))
                TextField("", text: $worktreePathInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: worktreePathInput) { _, newValue in
                        customWorktreePath = newValue != defaultWorktreePath().path
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Label (optional):")
                    .font(.system(size: 13))
                TextField("Task label", text: $worktreeLabelDraft)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Open after create", isOn: $openWorktreeAfterCreate)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

            if let worktreeCreationErrorMessage {
                Text(worktreeCreationErrorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingCreateWorktreeSheet = false
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreatingWorktree)

                Button("Create Worktree") {
                    onRunRepositoryOperation("Creating worktree...") {
                        await createWorktree()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreateWorktree || isCreatingWorktree)
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 500)
    }

    private func deleteBranch(_ branch: String, force: Bool = false) async {
        do {
            let support = GitBranchUndoSupport()
            let tip = try await support.tip(of: branch, in: repositoryURL)
            let upstream = await support.upstream(of: branch, in: repositoryURL)
            _ = try await GitStatusService.shared.deleteBranch(name: branch, force: force, in: repositoryURL)

            await MainActor.run {
                var undoOperations: [GitUndoOperation] = [
                    .createLocalBranch(name: branch, startPoint: tip, checkout: false)
                ]

                if let upstream {
                    undoOperations.append(.setUpstream(branch: branch, upstream: upstream))
                }

                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Delete branch \(branch)",
                        undoOperation: .sequence(undoOperations),
                        redoOperation: .deleteLocalBranch(name: branch, force: force, expectedTip: tip)
                    )
                )
            }

            NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func deleteBranchesWithPrefix(_ prefix: String, force: Bool) async {
        let toDelete = branchesUnderPrefix(prefix).filter { $0 != currentBranch }
        guard !toDelete.isEmpty else { return }

        var undoSequences: [GitUndoOperation] = []
        var redoOperations: [GitUndoOperation] = []
        var failed: [String] = []
        let support = GitBranchUndoSupport()

        for branch in toDelete {
            do {
                let tip = try await support.tip(of: branch, in: repositoryURL)
                let upstream = await support.upstream(of: branch, in: repositoryURL)
                _ = try await GitStatusService.shared.deleteBranch(name: branch, force: force, in: repositoryURL)

                var undoOps: [GitUndoOperation] = [
                    .createLocalBranch(name: branch, startPoint: tip, checkout: false)
                ]
                if let upstream {
                    undoOps.append(.setUpstream(branch: branch, upstream: upstream))
                }
                undoSequences.append(.sequence(undoOps))
                redoOperations.append(.deleteLocalBranch(name: branch, force: force, expectedTip: tip))
            } catch {
                failed.append(branch)
            }
        }

        await MainActor.run {
            if !undoSequences.isEmpty {
                let label = "Delete \(undoSequences.count) branch\(undoSequences.count == 1 ? "" : "es") in \(prefix)/"
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: label,
                        undoOperation: .sequence(undoSequences),
                        redoOperation: .sequence(redoOperations)
                    )
                )
            }
            if !failed.isEmpty {
                errorMessage = "Failed to delete: \(failed.joined(separator: ", "))"
                showingError = true
            }
        }

        NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
    }

    private func branchesUnderPrefix(_ prefix: String) -> [String] {
        var leaves: [String] = []
        func collect(_ nodes: [BranchNode]) {
            for node in nodes {
                if node.isFolder {
                    collect(node.children)
                } else {
                    leaves.append(node.fullPath)
                }
            }
        }
        collect(branchNodes)
        return leaves.filter { $0.hasPrefix(prefix + "/") }.sorted()
    }

    private func loadBranches(force: Bool = false) async {
        if !force && hasLoadedBranches {
            return
        }

        isLoadingBranches = true
        defer { isLoadingBranches = false }

        let locals = await GitStatusService.shared.localBranches(in: repositoryURL)
        let current = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        let filteredLocals = locals.filter { $0 != "HEAD" && !$0.contains("HEAD detached") }
        let tree = SidebarTreeBuilder.buildTree(from: filteredLocals)
        let allFolders = collectFolderPaths(from: tree)

        var syncMap: [String: BranchSyncStatus] = [:]
        await withTaskGroup(of: (String, BranchSyncStatus)?.self) { group in
            for branch in locals {
                group.addTask {
                    if let status = await GitStatusService.shared.branchSyncStatus(for: branch, in: repositoryURL) {
                        return (branch, status)
                    }
                    return nil
                }
            }

            for await result in group {
                if let (branch, status) = result {
                    syncMap[branch] = status
                }
            }
        }

        var headHashValue = ""
        if current.isEmpty, let hash = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL) {
            headHashValue = String(hash.prefix(7))
        }

        await MainActor.run {
            branchNodes = tree
            currentBranch = current
            headHash = headHashValue
            branchSyncStatus = syncMap
            let reveal = SidebarTreeBuilder.expandedFolderPaths(revealing: current)
                .intersection(allFolders)
            if hasLoadedBranches {
                // Subsequent reloads: preserve user-expanded folders, reveal the
                // current branch, and drop folders that no longer exist.
                expandedFolders = expandedFolders.union(reveal).intersection(allFolders)
            } else {
                // First load: reveal the current branch.
                expandedFolders = reveal
            }
            hasLoadedBranches = true
        }
    }

    private func loadWorktrees(force: Bool = false) async {
        if !force && hasLoadedWorktrees {
            return
        }

        isLoadingWorktrees = true
        defer { isLoadingWorktrees = false }

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repositoryURL)
        await MainActor.run {
            worktreeEntries = entries
            hasLoadedWorktrees = true
        }
    }

    private func loadTags() async {
        isLoadingTags = true
        defer { isLoadingTags = false }

        let tags = await GitStatusService.shared.tags(in: repositoryURL)
        let tree = SidebarTreeBuilder.buildTree(from: tags)
        let allFolders = collectFolderPaths(from: tree)

        await MainActor.run {
            tagNodes = tree
            if expandedTagFolders.isEmpty {
                expandedTagFolders = allFolders
            }
        }
    }

    private func loadRemotes() async {
        isLoadingRemotes = true
        defer { isLoadingRemotes = false }

        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        var fetchedBranchesByRemote: [String: [String]] = [:]
        for remote in remotes {
            fetchedBranchesByRemote[remote] = await GitStatusService.shared.remoteBranches(remote: remote, in: repositoryURL)
        }
        let upstreams = await GitStatusService.shared.localBranchUpstreams(in: repositoryURL)

        let tree = SidebarTreeBuilder.buildRemoteTree(remoteBranchesByRemote: fetchedBranchesByRemote)
        await MainActor.run {
            remoteNodes = tree
            remoteNames = remotes
            branchesByRemote = fetchedBranchesByRemote
            upstreamByBranch = upstreams
            if expandedRemoteFolders.isEmpty {
                expandedRemoteFolders = []
            }
        }
    }

    private func loadStashes() async {
        isLoadingStashes = true
        defer { isLoadingStashes = false }

        let stashes = await GitStatusService.shared.stashes(in: repositoryURL)
        await MainActor.run {
            stashEntries = stashes
        }
    }

    private func collectFolderPaths(from nodes: [BranchNode]) -> Set<String> {
        var paths = Set<String>()
        for node in nodes where node.isFolder {
            paths.insert(node.fullPath)
            paths.formUnion(collectFolderPaths(from: node.children))
        }
        return paths
    }

    private func isCurrentRepositoryWorktree(_ entry: WorktreeEntry) -> Bool {
        entry.path.standardizedFileURL == repositoryURL.standardizedFileURL
    }

    private func isMissingWorktree(_ entry: WorktreeEntry) -> Bool {
        !isCurrentRepositoryWorktree(entry)
            && (entry.dirtyCount < 0 || !FileManager.default.fileExists(atPath: entry.path.path))
    }

    private func selectWorktree(_ entry: WorktreeEntry) {
        if isMissingWorktree(entry) {
            showMissingWorktreeAlert(for: entry)
            return
        }

        selection = .worktree(entry.path)
    }

    private func openWorktree(_ entry: WorktreeEntry) {
        if isMissingWorktree(entry) {
            showMissingWorktreeAlert(for: entry)
            return
        }

        onRequestOpenWorktree(entry.path)
    }

    private func showMissingWorktreeAlert(for entry: WorktreeEntry) {
        missingWorktreeEntry = entry
        showingMissingWorktreeAlert = true
    }

    private func beginEditingWorktreeLabel(_ entry: WorktreeEntry) {
        worktreeToLabel = entry
        worktreeLabelInput = entry.label ?? ""
    }

    private func beginLockingWorktree(_ entry: WorktreeEntry) {
        worktreeToLock = entry
        worktreeLockReasonInput = ""
    }

    private func beginMovingWorktree(_ entry: WorktreeEntry) {
        worktreeToMove = entry
        worktreeMovePathInput = suggestedMovedWorktreePath(for: entry).path
        worktreeMoveErrorMessage = nil
    }

    private func saveWorktreeLabel() async {
        guard let entry = worktreeToLabel else { return }

        do {
            try await GitStatusService.shared.setWorktreeLabel(worktreeLabelInput, for: entry.path, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                worktreeToLabel = nil
                worktreeLabelInput = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func clearWorktreeLabel(_ entry: WorktreeEntry) async {
        do {
            try await GitStatusService.shared.removeWorktreeLabel(for: entry.path, in: repositoryURL)
            await loadWorktrees(force: true)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func lockWorktree(_ entry: WorktreeEntry) async {
        await MainActor.run {
            isUpdatingWorktreeLock = true
        }
        defer {
            Task { @MainActor in
                isUpdatingWorktreeLock = false
            }
        }

        do {
            try await GitStatusService.shared.lockWorktree(
                at: entry.path,
                reason: worktreeLockReasonInput,
                in: repositoryURL
            )
            await loadWorktrees(force: true)
            await MainActor.run {
                worktreeToLock = nil
                worktreeLockReasonInput = ""
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func unlockWorktree(_ entry: WorktreeEntry) async {
        do {
            try await GitStatusService.shared.unlockWorktree(at: entry.path, in: repositoryURL)
            await loadWorktrees(force: true)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func pruneWorktrees() async {
        do {
            try await GitStatusService.shared.pruneWorktrees(in: repositoryURL)
            await loadWorktrees(force: true)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func prepareCreateWorktreeSheet() async {
        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        let current = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        let root: URL
        if let gitDirectory = try? await GitStatusService.shared.gitCommonDirectory(in: repositoryURL) {
            root = gitDirectory.deletingLastPathComponent()
        } else {
            root = repositoryURL
        }

        await MainActor.run {
            currentWorktreeBranch = current
            availableWorktreeBranches = branches.filter { !$0.isEmpty }
            selectedExistingWorktreeBranch = preferredExistingWorktreeBranch(from: branches, currentBranch: current)
            newWorktreeBaseBranch = current.isEmpty ? (branches.first ?? "") : current
            newWorktreeBranchName = ""
            worktreeRootURL = root
            customWorktreePath = false
            worktreeLabelDraft = ""
            worktreeCreationErrorMessage = nil
            isCreatingWorktree = false
            openWorktreeAfterCreate = true
            refreshWorktreePathIfNeeded(force: true)
            showingCreateWorktreeSheet = true
        }
    }

    private func preferredExistingWorktreeBranch(from branches: [String], currentBranch: String) -> String {
        if let other = branches.first(where: { $0 != currentBranch }) {
            return other
        }
        return branches.first ?? ""
    }

    private func refreshWorktreePathIfNeeded(force: Bool) {
        guard force || !customWorktreePath else { return }
        worktreePathInput = defaultWorktreePath().path
        customWorktreePath = false
    }

    private func defaultWorktreePath() -> URL {
        let baseRoot = worktreeRootURL ?? repositoryURL
        let container = baseRoot.appendingPathComponent(".worktrees", isDirectory: true)
        return container.appendingPathComponent(defaultWorktreeFolderName(), isDirectory: true)
    }

    private func defaultWorktreeFolderName() -> String {
        switch createWorktreeMode {
        case .existingBranch:
            return sanitizedWorktreeFolderComponent(selectedExistingWorktreeBranch)
        case .newBranch:
            return sanitizedWorktreeFolderComponent(sanitizedWorktreeBranchName(newWorktreeBranchName))
        }
    }

    private func sanitizedWorktreeBranchName(_ input: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_/")
        var sanitized = ""
        for scalar in input.unicodeScalars {
            if allowed.contains(scalar) {
                sanitized.append(Character(scalar))
            } else {
                sanitized.append("-")
            }
        }

        while sanitized.contains("//") {
            sanitized = sanitized.replacingOccurrences(of: "//", with: "/")
        }

        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-/"))
    }

    private func sanitizedWorktreeFolderComponent(_ input: String) -> String {
        let candidate = input.replacingOccurrences(of: "/", with: "-")
        let trimmed = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        return trimmed.isEmpty ? "worktree" : trimmed
    }

    private func suggestedMovedWorktreePath(for entry: WorktreeEntry) -> URL {
        let currentPath = entry.path.standardizedFileURL
        let parent = currentPath.deletingLastPathComponent()
        let newName = currentPath.lastPathComponent + "-renamed"
        return parent.appendingPathComponent(newName, isDirectory: true)
    }

    private func createWorktree() async {
        let path = URL(fileURLWithPath: worktreePathInput)
        let target: WorktreeAddTarget
        let trimmedBaseBranch = newWorktreeBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        switch createWorktreeMode {
        case .existingBranch:
            target = .existingBranch(selectedExistingWorktreeBranch)
        case .newBranch:
            target = .newBranch(
                name: sanitizedWorktreeBranchName(newWorktreeBranchName),
                base: trimmedBaseBranch.isEmpty ? nil : trimmedBaseBranch
            )
        }

        await MainActor.run {
            isCreatingWorktree = true
            worktreeCreationErrorMessage = nil
        }
        defer {
            Task { @MainActor in
                isCreatingWorktree = false
            }
        }

        do {
            try await GitStatusService.shared.addWorktree(
                at: path,
                target: target,
                label: worktreeLabelDraft,
                in: repositoryURL
            )
            await loadWorktrees(force: true)
            await MainActor.run {
                showingCreateWorktreeSheet = false
                worktreeCreationErrorMessage = nil
            }
            if openWorktreeAfterCreate {
                await MainActor.run {
                    onRequestOpenWorktree(path)
                }
            }
        } catch {
            await MainActor.run {
                worktreeCreationErrorMessage = error.localizedDescription
            }
        }
    }

    private func moveWorktree(_ entry: WorktreeEntry) async {
        await MainActor.run {
            isMovingWorktree = true
            worktreeMoveErrorMessage = nil
        }
        defer {
            Task { @MainActor in
                isMovingWorktree = false
            }
        }

        let destination = URL(fileURLWithPath: worktreeMovePathInput)

        do {
            try await GitStatusService.shared.moveWorktree(from: entry.path, to: destination, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                worktreeToMove = nil
                worktreeMovePathInput = ""
                worktreeMoveErrorMessage = nil
            }
        } catch {
            await MainActor.run {
                worktreeMoveErrorMessage = error.localizedDescription
            }
        }
    }

    private func chooseReplacementWorktreeFolder(for entry: WorktreeEntry) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select the new location for \(entry.displayTitle)"
            panel.prompt = "Change Folder"

            panel.beginSheetModal(for: NSApp.keyWindow!) { result in
                missingWorktreeEntry = nil

                guard result == .OK, let url = panel.url else {
                    return
                }

                Task {
                    await repairMissingWorktree(entry, newPath: url)
                }
            }
        }
    }

    private func repairMissingWorktree(_ entry: WorktreeEntry, newPath: URL) async {
        do {
            try await GitStatusService.shared.repairWorktreeLocation(from: entry.path, to: newPath, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                selection = .worktree(newPath)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func prepareCheckoutWorktreeSheet(for entry: WorktreeEntry) async {
        let branches = await GitStatusService.shared.localBranches(in: repositoryURL).filter { !$0.isEmpty }
        let selectedBranch = branches.contains(entry.branch ?? "") ? (entry.branch ?? "") : (branches.first ?? "")

        await MainActor.run {
            worktreeToCheckout = entry
            availableWorktreeCheckoutBranches = branches
            selectedWorktreeCheckoutBranch = selectedBranch
            worktreeCheckoutErrorMessage = nil
            pendingWorktreeForceCheckout = nil
            showingWorktreeForceCheckoutConfirmation = false
        }
    }

    private func checkoutWorktree(_ entry: WorktreeEntry, force: Bool) async {
        await MainActor.run {
            isCheckingOutWorktreeBranch = true
            worktreeCheckoutErrorMessage = nil
            showingWorktreeForceCheckoutConfirmation = false
        }
        defer {
            Task { @MainActor in
                isCheckingOutWorktreeBranch = false
            }
        }

        do {
            try await GitStatusService.shared.checkoutBranch(
                selectedWorktreeCheckoutBranch,
                inWorktree: entry.path,
                force: force,
                repositoryURL: repositoryURL
            )
            await loadWorktrees(force: true)
            await MainActor.run {
                worktreeToCheckout = nil
                worktreeCheckoutErrorMessage = nil
                selectedWorktreeCheckoutBranch = ""
                availableWorktreeCheckoutBranches = []
                pendingWorktreeForceCheckout = nil
            }
        } catch {
            await MainActor.run {
                worktreeCheckoutErrorMessage = error.localizedDescription
                pendingWorktreeForceCheckout = nil
            }
        }
    }

    private func deleteMissingWorktree(_ entry: WorktreeEntry) async {
        do {
            try await GitStatusService.shared.removeWorktree(at: entry.path, force: true, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                missingWorktreeEntry = nil
                showingMissingWorktreeAlert = false
                if selection == .worktree(entry.path) {
                    selection = nil
                }
            }
        } catch {
            await MainActor.run {
                missingWorktreeEntry = nil
                showingMissingWorktreeAlert = false
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func removeWorktree(_ entry: WorktreeEntry, force: Bool) async {
        do {
            try await GitStatusService.shared.removeWorktree(at: entry.path, force: force, in: repositoryURL)
            await loadWorktrees(force: true)
            await MainActor.run {
                pendingWorktreeRemoval = nil
                showingWorktreeRemovalConfirmation = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

#Preview {
    SidebarView(
        repositoryURL: URL(fileURLWithPath: "/tmp"),
        selection: .constant(nil),
        isBranchSyncing: { _ in false },
        onRequestCheckout: { _, _ in },
        onRequestFetchBranch: { _ in },
        onRequestPullTracked: { _ in },
        onRequestPushToTracked: { _ in },
        onRequestRenameBranch: { _ in },
        onRequestCreatePullRequest: { _ in },
        onRequestRebaseOnto: { _ in },
        onRequestMergeBranchIntoCurrent: { _ in },
        onRequestOpenWorktree: { _ in },
        onRequestOpenWorktreeInTerminal: { _ in }
    )
    .environmentObject(AppState.shared)
}
