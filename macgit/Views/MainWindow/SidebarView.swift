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

struct SidebarView: View {
    @EnvironmentObject private var appUpdateController: AppUpdateController
    @EnvironmentObject var appState: AppState

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
    let onRequestOpenSubmodule: (URL) -> Void
    let onRequestShowSubmoduleInFinder: (URL) -> Void
    let onRequestOpenSubmoduleInTerminal: (URL) -> Void
    let onRequestAddSubmodule: () -> Void
    let onRequestAddLinkSubtree: () -> Void
    let onRequestCreateBranch: () -> Void
    let onRequestCreateTag: () -> Void
    let onRequestShowSubtreeInFinder: (URL) -> Void
    let onRequestOpenSubtreeInTerminal: (URL) -> Void
    let onRequestPullSubtree: (GitSubtreeEntry) -> Void
    let onRequestPushSubtree: (GitSubtreeEntry) -> Void
    let onRequestUpdateSubtreeLink: (GitSubtreeEntry) async throws -> Void
    let onRequestUnlinkSubtree: (GitSubtreeEntry) async throws -> Void
    let onRequestInitializeSubmodule: (String) -> Void
    let onRequestUpdateSubmodule: (String, SubmoduleUpdateMode) -> Void
    let onRequestSynchronizeSubmoduleURL: (String) -> Void
    let onRequestUpdateSubmoduleSettings: (String, String, String?) async throws -> Void
    let onRequestDeinitializeSubmodule: (String, Bool) async throws -> Void
    let onRequestRemoveSubmodule: (String, Bool) async throws -> Void
    let onRequestSearch: () -> Void
    let onRequestDragDrop: (GitDragDropRequest) -> Void
    let onRunRepositoryOperation: RepositoryOperationRunner

    @State var branchNodes: [BranchNode] = []
    @State var currentBranch: String = ""
    @State var headHash: String = ""
    @State var branchSyncStatus: [String: BranchSyncStatus] = [:]
    @State var activeBranchSyncLoadID: UUID?
    @State var loadedBranchSyncBranches: Set<String> = []
    @State var syncingBranchSyncBranches: Set<String> = []
    @State var expandedFolders: Set<String> = []
    @State var hasLoadedBranches = false
    @State var isLoadingBranches = false
    @State var tagNodes: [BranchNode] = []
    @State var isLoadingTags = false
    @State var expandedTagFolders: Set<String> = []
    @State var remoteNodes: [BranchNode] = []
    @State var remoteNames: [String] = []
    @State var branchesByRemote: [String: [String]] = [:]
    @State var upstreamByBranch: [String: String] = [:]
    @State var isLoadingRemotes = false
    @State var expandedRemoteFolders: Set<String> = []
    @State var stashEntries: [StashEntry] = []
    @State var isLoadingStashes = false
    @State var submoduleEntries: [GitSubmoduleEntry] = []
    @State var hasLoadedSubmodules = false
    @State var isLoadingSubmodules = false
    @State var activeSubmoduleLoadID: UUID?
    @State var submoduleToEdit: GitSubmoduleEntry?
    @State var submoduleToDeinitialize: GitSubmoduleEntry?
    @State var submoduleToRemove: GitSubmoduleEntry?
    @State var subtreeEntries: [GitSubtreeEntry] = []
    @State var hasLoadedSubtrees = false
    @State var isLoadingSubtrees = false
    @State var subtreeToEdit: GitSubtreeEntry?
    @State var subtreeToUnlink: GitSubtreeEntry?
    @State var worktreeEntries: [WorktreeEntry] = []
    @State var hasLoadedWorktrees = false
    @State var isLoadingWorktrees = false
    @State var worktreeToLabel: WorktreeEntry?
    @State var worktreeLabelInput = ""
    @State var worktreeToLock: WorktreeEntry?
    @State var worktreeLockReasonInput = ""
    @State var isUpdatingWorktreeLock = false
    @State var worktreeToMove: WorktreeEntry?
    @State var worktreeMovePathInput = ""
    @State var worktreeMoveErrorMessage: String?
    @State var isMovingWorktree = false
    @State var worktreeToCheckout: WorktreeEntry?
    @State var availableWorktreeCheckoutBranches: [String] = []
    @State var selectedWorktreeCheckoutBranch = ""
    @State var worktreeCheckoutErrorMessage: String?
    @State var isCheckingOutWorktreeBranch = false
    @State var pendingWorktreeForceCheckout: WorktreeEntry?
    @State var showingWorktreeForceCheckoutConfirmation = false
    @State var missingWorktreeEntry: WorktreeEntry?
    @State var showingMissingWorktreeAlert = false
    @State var pendingWorktreeRemoval: WorktreeEntry?
    @State var showingWorktreeRemovalConfirmation = false
    @State var showingPruneWorktreesConfirmation = false
    @State var createWorktreeMode: WorktreeCreationMode = .existingBranch
    @State var availableWorktreeBranches: [String] = []
    @State var currentWorktreeBranch = ""
    @State var selectedExistingWorktreeBranch = ""
    @State var newWorktreeBranchName = ""
    @State var newWorktreeBaseBranch = ""
    @State var worktreePathInput = ""
    @State var customWorktreePath = false
    @State var worktreeLabelDraft = ""
    @State var openWorktreeAfterCreate = true
    @State var showingCreateWorktreeSheet = false
    @State var isCreatingWorktree = false
    @State var worktreeCreationErrorMessage: String?
    @State var worktreeRootURL: URL?

    @State var sectionStates = SidebarSectionState()

    @State var errorMessage = ""
    @State var showingError = false
    @State var deleteConfirmationTarget: DeleteConfirmationTarget?
    @State var remoteBranchDeleteTarget: RemoteBranchDeleteTarget?
    @State var forceDeleteBranch = false
    @State var activeDropTarget: GitDragTarget?
    @State var activeDropLabel: String?
    @State var isCurrentBranchDropTargeted = false
    @State var activeBranchDragPayload: GitDragPayload?

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
        onRequestOpenSubmodule: @escaping (URL) -> Void = { _ in },
        onRequestShowSubmoduleInFinder: @escaping (URL) -> Void = { _ in },
        onRequestOpenSubmoduleInTerminal: @escaping (URL) -> Void = { _ in },
        onRequestAddSubmodule: @escaping () -> Void = {},
        onRequestAddLinkSubtree: @escaping () -> Void = {},
        onRequestCreateBranch: @escaping () -> Void = {},
        onRequestCreateTag: @escaping () -> Void = {},
        onRequestShowSubtreeInFinder: @escaping (URL) -> Void = { _ in },
        onRequestOpenSubtreeInTerminal: @escaping (URL) -> Void = { _ in },
        onRequestPullSubtree: @escaping (GitSubtreeEntry) -> Void = { _ in },
        onRequestPushSubtree: @escaping (GitSubtreeEntry) -> Void = { _ in },
        onRequestUpdateSubtreeLink: @escaping (GitSubtreeEntry) async throws -> Void = { _ in },
        onRequestUnlinkSubtree: @escaping (GitSubtreeEntry) async throws -> Void = { _ in },
        onRequestInitializeSubmodule: @escaping (String) -> Void = { _ in },
        onRequestUpdateSubmodule: @escaping (String, SubmoduleUpdateMode) -> Void = { _, _ in },
        onRequestSynchronizeSubmoduleURL: @escaping (String) -> Void = { _ in },
        onRequestUpdateSubmoduleSettings: @escaping (String, String, String?) async throws -> Void = { _, _, _ in },
        onRequestDeinitializeSubmodule: @escaping (String, Bool) async throws -> Void = { _, _ in },
        onRequestRemoveSubmodule: @escaping (String, Bool) async throws -> Void = { _, _ in },
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
        self.onRequestOpenSubmodule = onRequestOpenSubmodule
        self.onRequestShowSubmoduleInFinder = onRequestShowSubmoduleInFinder
        self.onRequestOpenSubmoduleInTerminal = onRequestOpenSubmoduleInTerminal
        self.onRequestAddSubmodule = onRequestAddSubmodule
        self.onRequestAddLinkSubtree = onRequestAddLinkSubtree
        self.onRequestCreateBranch = onRequestCreateBranch
        self.onRequestCreateTag = onRequestCreateTag
        self.onRequestShowSubtreeInFinder = onRequestShowSubtreeInFinder
        self.onRequestOpenSubtreeInTerminal = onRequestOpenSubtreeInTerminal
        self.onRequestPullSubtree = onRequestPullSubtree
        self.onRequestPushSubtree = onRequestPushSubtree
        self.onRequestUpdateSubtreeLink = onRequestUpdateSubtreeLink
        self.onRequestUnlinkSubtree = onRequestUnlinkSubtree
        self.onRequestInitializeSubmodule = onRequestInitializeSubmodule
        self.onRequestUpdateSubmodule = onRequestUpdateSubmodule
        self.onRequestSynchronizeSubmoduleURL = onRequestSynchronizeSubmoduleURL
        self.onRequestUpdateSubmoduleSettings = onRequestUpdateSubmoduleSettings
        self.onRequestDeinitializeSubmodule = onRequestDeinitializeSubmodule
        self.onRequestRemoveSubmodule = onRequestRemoveSubmodule
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

            sidebarContent
        }
    }

    var branchSectionActions: SidebarBranchSectionActions {
        SidebarBranchSectionActions(
            toggleSection: { toggleSection(.branches) },
            toggleFolder: toggleFolder,
            select: { selection = $0 },
            checkout: { onRequestCheckout($0, false) },
            fetch: onRequestFetchBranch,
            pullTracked: onRequestPullTracked,
            pushTracked: onRequestPushToTracked,
            rename: onRequestRenameBranch,
            createPullRequest: onRequestCreatePullRequest,
            createBranchFrom: onRequestCreateBranchFromBranch,
            createTagFrom: onRequestCreateTagFromBranch,
            rebaseOnto: onRequestRebaseOnto,
            mergeIntoCurrent: onRequestMergeBranchIntoCurrent,
            pushToRemote: onRequestPushBranchToRemote,
            trackRemoteBranch: onRequestTrackRemoteBranch,
            confirmDelete: { deleteConfirmationTarget = $0 },
            makeItemProvider: makeBranchItemProvider,
            setHeaderDropTargeted: updateBranchesHeaderDropTarget,
            setCurrentDropTargeted: updateCurrentBranchDropTarget,
            currentDropLabel: currentBranchDropLabel,
            drop: dropActions
        )
    }

    var tagSectionActions: SidebarTagSectionActions {
        SidebarTagSectionActions(
            toggleSection: { toggleSection(.tags) },
            toggleFolder: toggleTagFolder,
            select: { selection = $0 },
            checkout: { onRequestCheckout($0, true) },
            showDetails: onRequestTagDetails,
            diffAgainstCurrent: onRequestDiffTagAgainstCurrent,
            pushToRemote: onRequestPushTagToRemote,
            delete: onRequestDeleteTag,
            setHeaderDropTargeted: updateTagsHeaderDropTarget,
            drop: dropActions
        )
    }

    var remoteSectionActions: SidebarRemoteSectionActions {
        SidebarRemoteSectionActions(
            toggleSection: { toggleSection(.remotes) },
            toggleFolder: toggleRemoteFolder,
            select: { selection = $0 },
            checkoutFromRow: { fullPath in
                Task {
                    await checkoutRemoteBranch(fullPath)
                }
            },
            checkoutFromContextMenu: { fullPath in
                onRunRepositoryOperation("Checking out \(fullPath)...") {
                    await checkoutRemoteBranch(fullPath)
                }
            },
            pullIntoCurrent: onRequestPullRemoteBranch,
            confirmDelete: { remoteBranchDeleteTarget = $0 },
            createPullRequest: onRequestCreatePullRequestForRemote,
            makePayload: makeRemoteBranchPayload,
            finishDrag: finishRemoteBranchDrag,
            setHeaderDropTargeted: updateRemotesHeaderDropTarget,
            drop: dropActions
        )
    }

    var stashSectionActions: SidebarStashSectionActions {
        SidebarStashSectionActions(
            toggleSection: { toggleSection(.stashes) },
            select: { selection = $0 },
            apply: onRequestApplyStash,
            delete: onRequestDeleteStash,
            makeItemProvider: makeStashItemProvider,
            setHeaderDropTargeted: updateStashesHeaderDropTarget,
            drop: dropActions
        )
    }

    var submoduleSectionActions: SidebarSubmoduleSectionActions {
        SidebarSubmoduleSectionActions(
            toggleSection: { toggleSection(.submodules) },
            open: onRequestOpenSubmodule,
            showInFinder: onRequestShowSubmoduleInFinder,
            openInTerminal: onRequestOpenSubmoduleInTerminal,
            initialize: onRequestInitializeSubmodule,
            update: onRequestUpdateSubmodule,
            synchronizeURL: onRequestSynchronizeSubmoduleURL,
            edit: { submoduleToEdit = $0 },
            deinitialize: presentDeinitializeSubmoduleConfirmation,
            remove: presentRemoveSubmoduleConfirmation
        )
    }

    var subtreeSectionActions: SidebarSubtreeSectionActions {
        SidebarSubtreeSectionActions(
            toggleSection: { toggleSection(.subtrees) },
            showInFinder: onRequestShowSubtreeInFinder,
            openInTerminal: onRequestOpenSubtreeInTerminal,
            pull: onRequestPullSubtree,
            push: onRequestPushSubtree,
            edit: { subtreeToEdit = $0 },
            unlink: { subtreeToUnlink = $0 }
        )
    }

    var worktreeSectionActions: SidebarWorktreeSectionActions {
        SidebarWorktreeSectionActions(
            toggleSection: { toggleSection(.worktrees) },
            prepareCreate: {
                onRunRepositoryOperation("Preparing worktree creation...") {
                    await prepareCreateWorktreeSheet()
                }
            },
            confirmPrune: { showingPruneWorktreesConfirmation = true },
            select: selectWorktree,
            open: openWorktree,
            openInTerminal: onRequestOpenWorktreeInTerminal,
            editLabel: beginEditingWorktreeLabel,
            clearLabel: { entry in
                onRunRepositoryOperation("Clearing worktree label...") {
                    await clearWorktreeLabel(entry)
                }
            },
            editLock: beginLockingWorktree,
            unlock: { entry in
                onRunRepositoryOperation("Unlocking \(entry.displayTitle)...") {
                    await unlockWorktree(entry)
                }
            },
            move: beginMovingWorktree,
            switchBranch: { entry in
                onRunRepositoryOperation("Preparing branch switch...") {
                    await prepareCheckoutWorktreeSheet(for: entry)
                }
            },
            confirmRemoval: { entry in
                pendingWorktreeRemoval = entry
                showingWorktreeRemovalConfirmation = true
            }
        )
    }

    var dropActions: SidebarDropActions {
        SidebarDropActions(
            activePayload: { activeBranchDragPayload ?? GitDragPayloadStore.currentPayload() },
            canAccept: canAcceptDrop,
            handlePayload: { payload, target, optionKeyPressed in
                activeBranchDragPayload = nil
                GitDragPayloadStore.clear(ifMatching: payload)
                handleDrop([payload], target: target, optionKeyPressed: optionKeyPressed)
            },
            handleProviders: { providers, target, optionKeyPressed in
                activeBranchDragPayload = nil
                GitDragPayloadStore.clear()
                return handleDrop(
                    providers,
                    target: target,
                    optionKeyPressed: optionKeyPressed
                )
            },
            clearPayload: { payload in
                activeBranchDragPayload = nil
                if let payload {
                    GitDragPayloadStore.clear(ifMatching: payload)
                } else {
                    GitDragPayloadStore.clear()
                }
                clearDropHover()
            }
        )
    }

    private var sidebarContent: some View {
        sidebarList
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
            .modifier(
                SidebarWorktreePresentationModifier(
                    worktreeToLabel: $worktreeToLabel,
                    worktreeLabelInput: $worktreeLabelInput,
                    worktreeToLock: $worktreeToLock,
                    worktreeLockReasonInput: $worktreeLockReasonInput,
                    isUpdatingWorktreeLock: isUpdatingWorktreeLock,
                    worktreeToMove: $worktreeToMove,
                    worktreeMovePathInput: $worktreeMovePathInput,
                    worktreeMoveErrorMessage: $worktreeMoveErrorMessage,
                    canMoveWorktree: canMoveWorktree,
                    isMovingWorktree: isMovingWorktree,
                    worktreeToCheckout: $worktreeToCheckout,
                    availableWorktreeCheckoutBranches: $availableWorktreeCheckoutBranches,
                    selectedWorktreeCheckoutBranch: $selectedWorktreeCheckoutBranch,
                    worktreeCheckoutErrorMessage: $worktreeCheckoutErrorMessage,
                    canCheckoutWorktreeBranch: canCheckoutWorktreeBranch,
                    isCheckingOutWorktreeBranch: isCheckingOutWorktreeBranch,
                    showingCreateWorktreeSheet: $showingCreateWorktreeSheet,
                    createWorktreeMode: $createWorktreeMode,
                    availableWorktreeBranches: availableWorktreeBranches,
                    selectedExistingWorktreeBranch: $selectedExistingWorktreeBranch,
                    newWorktreeBranchName: $newWorktreeBranchName,
                    newWorktreeBaseBranch: $newWorktreeBaseBranch,
                    worktreePathInput: $worktreePathInput,
                    worktreeLabelDraft: $worktreeLabelDraft,
                    openWorktreeAfterCreate: $openWorktreeAfterCreate,
                    worktreeCreationErrorMessage: worktreeCreationErrorMessage,
                    canCreateWorktree: canCreateWorktree,
                    isCreatingWorktree: isCreatingWorktree,
                    showingWorktreeRemovalConfirmation: $showingWorktreeRemovalConfirmation,
                    showingMissingWorktreeAlert: $showingMissingWorktreeAlert,
                    showingWorktreeForceCheckoutConfirmation: $showingWorktreeForceCheckoutConfirmation,
                    showingPruneWorktreesConfirmation: $showingPruneWorktreesConfirmation,
                    pendingWorktreeRemoval: $pendingWorktreeRemoval,
                    pendingWorktreeForceCheckout: $pendingWorktreeForceCheckout,
                    missingWorktreeEntry: $missingWorktreeEntry,
                    worktreeRemovalNeedsForce: worktreeRemovalNeedsForce,
                    worktreeRemovalMessage: worktreeRemovalMessage,
                    saveWorktreeLabel: saveWorktreeLabel,
                    lockWorktree: lockWorktree,
                    moveWorktree: moveWorktree,
                    checkoutWorktree: checkoutWorktree,
                    onCreateWorktreeModeChange: { refreshWorktreePathIfNeeded(force: false) },
                    onSelectedExistingWorktreeBranchChange: { refreshWorktreePathIfNeeded(force: false) },
                    onNewWorktreeBranchNameChange: { refreshWorktreePathIfNeeded(force: false) },
                    onWorktreePathChange: { newValue in
                        customWorktreePath = newValue != defaultWorktreePath().path
                    },
                    createWorktree: createWorktree,
                    chooseReplacementWorktreeFolder: chooseReplacementWorktreeFolder,
                    deleteMissingWorktree: deleteMissingWorktree,
                    removeWorktree: removeWorktree,
                    pruneWorktrees: pruneWorktrees,
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            )
            .modifier(
                SidebarSubtreePresentationModifier(
                    subtreeToEdit: $subtreeToEdit,
                    subtreeToUnlink: $subtreeToUnlink,
                    updateSubtree: { updated in
                        try await onRequestUpdateSubtreeLink(updated)
                    },
                    unlinkSubtree: unlinkSubtree,
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            )
            .modifier(
                SubmoduleLifecyclePresentationModifier(
                    submoduleToEdit: $submoduleToEdit,
                    submoduleToDeinitialize: $submoduleToDeinitialize,
                    submoduleToRemove: $submoduleToRemove,
                    onSaveSettings: { entry, url, branch in
                        try await onRequestUpdateSubmoduleSettings(entry.path, url, branch)
                    },
                    onDeinitialize: runSubmoduleDeinitialize,
                    onRemove: runSubmoduleRemove,
                    onRunRepositoryOperation: onRunRepositoryOperation
                )
            )
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            sidebarRows
        }
        .listStyle(.sidebar)
        .contextMenu {
            Button("Add Submodule...", systemImage: "plus", action: onRequestAddSubmodule)
            Button("Add/Link Subtree...", systemImage: "plus", action: onRequestAddLinkSubtree)
            Divider()
            Button("New Branch...", systemImage: "arrow.triangle.branch", action: onRequestCreateBranch)
            Button("New Tag...", systemImage: "tag", action: onRequestCreateTag)
        }
        .task(id: "\(repositoryURL.path)|\(appState.showSubmodules)") {
            loadSectionStates()
            resetLazySectionData()
            await loadAllSections(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await loadAllSections(force: true)
                }
            }
        }
        .onChange(of: appState.showSubtrees) { _, isVisible in
            guard isVisible, sectionStates.subtreesExpanded else { return }
            Task {
                await loadSubtrees(force: false)
            }
        }
    }

    @ViewBuilder
    private var sidebarRows: some View {
        SidebarWorkspaceSection(onRequestSearch: onRequestSearch)

        SidebarBranchesSection(
            rows: visibleBranchRows,
            isExpanded: sectionStates.branchesExpanded,
            isLoading: isLoadingBranches,
            currentBranch: currentBranch,
            headHash: headHash,
            expandedFolders: expandedFolders,
            branchSyncStatus: branchSyncStatus,
            currentBranchFallbackSyncStatus: currentBranchFallbackSyncStatus,
            upstreamByBranch: upstreamByBranch,
            remoteNames: remoteNames,
            branchesByRemote: branchesByRemote,
            isCurrentBranchDropTargeted: isCurrentBranchDropTargeted,
            isHeaderDropTargeted: activeDropTarget == .branchesHeader,
            activeDropLabel: activeDropTarget == .branchesHeader ? activeDropLabel : nil,
            draggedRemoteBranch: draggedRemoteBranch,
            isBranchSyncing: isBranchSyncing,
            deletableBranchesForPrefix: { prefix in
                branchesUnderPrefix(prefix).filter { $0 != currentBranch }
            },
            makeBranchPayload: { makeBranchPayload(branchName: $0) },
            finishBranchDrag: { payload in
                activeBranchDragPayload = nil
                GitDragPayloadStore.clear(ifMatching: payload)
            },
            actions: branchSectionActions
        )

        SidebarWorktreesSection(
            currentRepositoryURL: repositoryURL,
            entries: worktreeEntries,
            isExpanded: sectionStates.worktreesExpanded,
            isLoading: isLoadingWorktrees,
            onOpenInNewWindow: onRequestOpenWorktree,
            actions: worktreeSectionActions
        )

        SidebarTagsSection(
            rows: visibleTagRows,
            isExpanded: sectionStates.tagsExpanded,
            isLoading: isLoadingTags,
            expandedFolders: expandedTagFolders,
            remoteNames: remoteNames,
            isHeaderDropTargeted: activeDropTarget == .tagsHeader,
            activeDropLabel: activeDropTarget == .tagsHeader ? activeDropLabel : nil,
            actions: tagSectionActions
        )

        SidebarRemotesSection(
            rows: visibleRemoteRows,
            isExpanded: sectionStates.remotesExpanded,
            isLoading: isLoadingRemotes,
            currentBranch: currentBranch,
            expandedFolders: expandedRemoteFolders,
            isHeaderDropTargeted: activeDropTarget == .remotesHeader,
            activeDropLabel: activeDropTarget == .remotesHeader ? activeDropLabel : nil,
            actions: remoteSectionActions
        )

        SidebarStashesSection(
            stashes: stashEntries,
            isExpanded: sectionStates.stashesExpanded,
            isLoading: isLoadingStashes,
            isHeaderDropTargeted: activeDropTarget == .stashesHeader,
            activeDropLabel: activeDropTarget == .stashesHeader ? activeDropLabel : nil,
            actions: stashSectionActions
        )

        if appState.showSubmodules {
            SidebarSubmodulesSection(
                repositoryURL: repositoryURL,
                entries: submoduleEntries,
                isExpanded: sectionStates.submodulesExpanded,
                isLoading: isLoadingSubmodules,
                onAddSubmodule: onRequestAddSubmodule,
                actions: submoduleSectionActions
            )
        }

        if appState.showSubtrees {
            SidebarSubtreesSection(
                repositoryURL: repositoryURL,
                entries: subtreeEntries,
                isExpanded: sectionStates.subtreesExpanded,
                isLoading: isLoadingSubtrees,
                onAddLinkSubtree: onRequestAddLinkSubtree,
                actions: subtreeSectionActions
            )
        }
    }

    private func presentDeinitializeSubmoduleConfirmation(_ entry: GitSubmoduleEntry) {
        let decision = SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: false), entry: entry)
        guard decision.requiresConfirmation else {
            errorMessage = decision.message ?? "This submodule cannot be deinitialized."
            showingError = true
            return
        }
        submoduleToDeinitialize = entry
    }

    private func presentRemoveSubmoduleConfirmation(_ entry: GitSubmoduleEntry) {
        let decision = SubmoduleLifecyclePolicy.decision(for: .remove(force: false), entry: entry)
        guard decision.requiresConfirmation else {
            errorMessage = decision.message ?? "This submodule cannot be removed."
            showingError = true
            return
        }
        submoduleToRemove = entry
    }

    private func runSubmoduleDeinitialize(_ entry: GitSubmoduleEntry, force: Bool) {
        submoduleToDeinitialize = nil
        onRunRepositoryOperation("Deinitializing \(entry.path)...") {
            do {
                try await onRequestDeinitializeSubmodule(entry.path, force)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func runSubmoduleRemove(_ entry: GitSubmoduleEntry, force: Bool) {
        submoduleToRemove = nil
        onRunRepositoryOperation("Removing submodule \(entry.path)...") {
            do {
                try await onRequestRemoveSubmodule(entry.path, force)
                await MainActor.run {
                    selection = .item(.fileStatus)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func loadSectionStates() {
        sectionStates = SidebarSettingsStore.shared.state(for: repositoryURL.path)
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
        loadedBranchSyncBranches = []
        syncingBranchSyncBranches = []
        expandedFolders = []
        hasLoadedBranches = false
        isLoadingBranches = false

        worktreeEntries = []
        hasLoadedWorktrees = false
        isLoadingWorktrees = false

        submoduleEntries = []
        hasLoadedSubmodules = false
        isLoadingSubmodules = false

        subtreeEntries = []
        hasLoadedSubtrees = false
        isLoadingSubtrees = false
    }

    private func loadVisibleSections(force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            if sectionStates.branchesExpanded {
                group.addTask {
                    await loadBranches(force: force)
                }
            }
            if sectionStates.worktreesExpanded {
                group.addTask {
                    await loadWorktrees(force: force)
                }
            }
            if appState.showSubmodules && sectionStates.submodulesExpanded {
                group.addTask {
                    await loadSubmodules(force: force)
                }
            }
            if appState.showSubtrees && sectionStates.subtreesExpanded {
                group.addTask {
                    await loadSubtrees(force: force)
                }
            }
        }
    }

    private func loadAllSections(force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await loadVisibleSections(force: force)
            }
            group.addTask {
                await loadTags()
            }
            group.addTask {
                await loadRemotes()
            }
            group.addTask {
                await loadStashes()
            }
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
        case .submodules:
            if appState.showSubmodules && sectionStates.submodulesExpanded {
                await loadSubmodules(force: false)
            }
        case .subtrees:
            if appState.showSubtrees && sectionStates.subtreesExpanded {
                await loadSubtrees(force: false)
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
            if let loadID = activeBranchSyncLoadID {
                startBranchSync(for: branchesUnderPrefix(path), loadID: loadID)
            }
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

        let (locals, current) = await (
            GitStatusService.shared.cachedLocalBranches(in: repositoryURL),
            GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        )
        let filteredLocals = locals.filter { $0 != "HEAD" && !$0.contains("HEAD detached") }
        let tree = SidebarTreeBuilder.buildTree(from: filteredLocals)
        let allFolders = collectFolderPaths(from: tree)
        let loadID = UUID()
        let hadLoadedBranches = hasLoadedBranches
        let currentBranchFolders = SidebarTreeBuilder.expandedFolderPaths(revealing: current)
            .intersection(allFolders)
        let expandedFoldersForLoad = hadLoadedBranches
            ? expandedFolders.union(currentBranchFolders).intersection(allFolders)
            : currentBranchFolders
        activeBranchSyncLoadID = loadID

        await MainActor.run {
            guard activeBranchSyncLoadID == loadID else { return }
            branchNodes = tree
            currentBranch = current
            headHash = ""
            branchSyncStatus = [:]
            loadedBranchSyncBranches = []
            syncingBranchSyncBranches = []
            if hadLoadedBranches {
                // Subsequent reloads: preserve user-expanded folders, reveal the
                // current branch, and drop folders that no longer exist.
                expandedFolders = expandedFoldersForLoad
            } else {
                // First load: reveal the current branch.
                expandedFolders = expandedFoldersForLoad
            }
            hasLoadedBranches = true
        }

        if current.isEmpty {
            Task {
                guard let hash = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL) else { return }
                await MainActor.run {
                    guard activeBranchSyncLoadID == loadID else { return }
                    headHash = String(hash.prefix(7))
                }
            }
        }

        let initiallyVisibleBranches = filteredLocals.filter { branch in
            branch == current
                || !branch.contains("/")
                || expandedFoldersForLoad.contains { folder in
                    branch.hasPrefix(folder + "/")
                }
        }
        startBranchSync(for: initiallyVisibleBranches, loadID: loadID)
    }

    private func startBranchSync(for branches: [String], loadID: UUID) {
        let pendingBranches = branches.filter {
            !loadedBranchSyncBranches.contains($0)
                && !syncingBranchSyncBranches.contains($0)
        }
        guard !pendingBranches.isEmpty else { return }

        syncingBranchSyncBranches.formUnion(pendingBranches)
        Task {
            await loadBranchSyncStatuses(for: pendingBranches, loadID: loadID)
        }
    }

    private func loadBranchSyncStatuses(for branches: [String], loadID: UUID) async {
        await withTaskGroup(of: (String, BranchSyncStatus?).self) { group in
            for branch in branches {
                group.addTask {
                    let status = await GitStatusService.shared.branchSyncStatus(
                        for: branch,
                        in: repositoryURL
                    )
                    return (branch, status)
                }
            }

            for await result in group {
                await MainActor.run {
                    guard activeBranchSyncLoadID == loadID else { return }
                    let (branch, status) = result
                    if let status {
                        branchSyncStatus[branch] = status
                    }
                    loadedBranchSyncBranches.insert(branch)
                    syncingBranchSyncBranches.remove(branch)
                }
            }
        }

        await MainActor.run {
            if activeBranchSyncLoadID == loadID {
                for branch in branches {
                    syncingBranchSyncBranches.remove(branch)
                }
            }
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

    @MainActor
    private func loadSubmodules(force: Bool = false) async {
        if !force && hasLoadedSubmodules {
            return
        }

        let loadID = UUID()
        activeSubmoduleLoadID = loadID
        isLoadingSubmodules = true

        do {
            let entries = try await GitStatusService.shared.submodules(in: repositoryURL)
            guard activeSubmoduleLoadID == loadID else { return }
            submoduleEntries = entries
            hasLoadedSubmodules = true
            isLoadingSubmodules = false
            activeSubmoduleLoadID = nil
            if case .submodule(let path) = selection,
               !entries.contains(where: { $0.path == path }) {
                selection = nil
            }
        } catch is CancellationError {
            if activeSubmoduleLoadID == loadID {
                isLoadingSubmodules = false
                activeSubmoduleLoadID = nil
            }
        } catch {
            guard activeSubmoduleLoadID == loadID else { return }
            hasLoadedSubmodules = true
            isLoadingSubmodules = false
            activeSubmoduleLoadID = nil
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func loadSubtrees(force: Bool = false) async {
        if !force && hasLoadedSubtrees {
            return
        }

        isLoadingSubtrees = true
        defer { isLoadingSubtrees = false }

        do {
            let entries = try await GitStatusService.shared.subtrees(in: repositoryURL)
            await MainActor.run {
                subtreeEntries = entries
                hasLoadedSubtrees = true
                if case .subtree(let id) = selection,
                   !entries.contains(where: { $0.id == id }) {
                    selection = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func unlinkSubtree(_ entry: GitSubtreeEntry) async {
        do {
            try await onRequestUnlinkSubtree(entry)
            await MainActor.run {
                subtreeToUnlink = nil
                if selection == .subtree(entry.id) {
                    selection = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
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
        let fetchedBranchesByRemote = await withTaskGroup(
            of: (String, [String]).self,
            returning: [String: [String]].self
        ) { group in
            for remote in remotes {
                group.addTask {
                    let branches = await GitStatusService.shared.cachedRemoteBranches(
                        remote: remote,
                        in: repositoryURL
                    )
                    return (remote, branches)
                }
            }

            var result: [String: [String]] = [:]
            for await (remote, branches) in group {
                result[remote] = branches
            }
            return result
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
        let branches = await GitStatusService.shared.cachedLocalBranches(in: repositoryURL)
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
        let branches = await GitStatusService.shared.cachedLocalBranches(in: repositoryURL).filter { !$0.isEmpty }
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
