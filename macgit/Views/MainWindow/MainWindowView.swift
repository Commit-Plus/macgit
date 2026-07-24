//
//  MainWindowView.swift
//  macgit
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
import SwiftUI

struct WindowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PendingCommitDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let commits: [GitDraggedCommit]
    let targetBranch: String
}

struct PendingBranchDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let sourceBranch: String
    let targetBranch: String
    var operation: GitDragBranchOperation
}

struct PendingPushBranchDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let branch: String
    let remote: String

    var remoteBranch: String {
        "\(remote)/\(branch)"
    }
}

struct PendingSubtreeOperation: Identifiable, Equatable {
    let operation: SubtreeOperation
    let entry: GitSubtreeEntry

    var id: String {
        "\(operation)-\(entry.id)"
    }
}

struct BranchTagStartPoint: Equatable {
    let branchName: String
    let hash: String
    let message: String

    var shortHash: String {
        String(hash.prefix(7))
    }
}

struct MainWindowView: View {
    let repositoryURL: URL
    @ObservedObject var providerAccountController: GitProviderAccountController
    let onOpenConnections: () -> Void
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    let repoSettingsStore = RepoSettingsStore.shared
    private let fileService = RepositorySettingsFileService()
    let undoExecutor = GitUndoExecutor()
    @State var selectedItem: SidebarSelection? = .item(.fileStatus)
    @State private var windowWidth: CGFloat = 0
    @State private var showingCommitSheet = false
    @State var showingPullSheet = false
    @State var showingPushSheet = false
    @State var showingFetchSheet = false
    @State var showingAddSubmoduleSheet = false
    @State var showingAddLinkSubtreeSheet = false
    @State var showingBranchSheet = false
    @State var branchSheetStartPoint: GitBranchStartPoint?
    @State var showingTagSheet = false
    @State var showingNewTagSheet = false
    @State var tagNameInput = ""
    @State var branchTagStartPoint: BranchTagStartPoint?
    @State var showingMergeSheet = false
    @State var showingStashSheet = false
    @State var showingCheckoutConfirmation = false
    @State var branchToCheckout: String = ""
    @State private var pendingRemoteBranchCheckout: RemoteBranchCheckoutTarget?
    @State private var showingRenameBranchSheet = false
    @State var branchToRename: String = ""
    @State var showingDetachedHeadConfirmation = false
    @State var tagToCheckout: String = ""
    @State private var displayedTagDetails: GitTagDetails?
    @State private var tagPendingDeletion: String?
    @State var pendingStashRef: String?
    @State var pendingStashAction: StashAction?
    @State var pendingStashPaths: [String] = []
    @StateObject var syncState = SyncState()
    @StateObject var undoManager = GitUndoManager()
    @StateObject var pullRequestController: PullRequestController
    @State private var repoIconName: String = "code-branch"
    @State private var remoteURLString: String = ""
    @State var selectedBranchName: String? = nil
    @State private var pullPreselectedBranch: String? = nil
    @State var showingSearchModal = false
    @State var showingRepositorySettings = false
    @State var pendingSearchFileOpenRequest: SearchFileOpenRequest?
    @State var repoSettings = RepoSettings.defaults(currentBranch: nil, remotes: [])
    @State var pendingConfirmedUndo: (entry: GitUndoEntry, action: GitUndoMenuAction)?
    @State var pendingCommitDropConfirmation: PendingCommitDropConfirmation?
    @State var pendingBranchDropConfirmation: PendingBranchDropConfirmation?
    @State var pendingPushBranchDropConfirmation: PendingPushBranchDropConfirmation?
    @State private var pendingSubtreeOperation: PendingSubtreeOperation?
    @State private var isPerformingBranchDropOperation = false
    @StateObject var operationProgress = RepositoryOperationProgress()

    init(
        repositoryURL: URL,
        providerAccountController: GitProviderAccountController,
        onOpenConnections: @escaping () -> Void = {}
    ) {
        self.repositoryURL = repositoryURL
        self.providerAccountController = providerAccountController
        self.onOpenConnections = onOpenConnections
        _pullRequestController = StateObject(wrappedValue: PullRequestController(
            providerAccountController: providerAccountController,
            tokenVault: KeychainGitProviderTokenVault(),
            services: [.github: GitHubPullRequestService(), .gitlab: GitLabPullRequestService()],
            openURL: NSWorkspace.shared.open
        ))
    }

    var body: some View {
        mainContent
            .alert("Error", isPresented: $syncState.showingError, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(syncState.errorMessage ?? "An unknown error occurred")
            })
            .alert("Conflict", isPresented: $syncState.showingConflict, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(syncState.conflictMessage ?? "Merge conflicts detected.")
            })
            .alert("Info", isPresented: $syncState.showingInfo, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(syncState.infoMessage ?? "")
            })
            .confirmationDialog(
                pendingConfirmedUndo?.action == .redo ? "Confirm Git Redo" : "Confirm Git Undo",
                isPresented: Binding(
                    get: { pendingConfirmedUndo != nil },
                    set: { isPresented in
                        if !isPresented {
                            if let pending = pendingConfirmedUndo {
                                switch pending.action {
                                case .undo:
                                    undoManager.restoreUndo(pending.entry)
                                case .redo:
                                    undoManager.restoreRedo(pending.entry)
                                }
                            }
                            pendingConfirmedUndo = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(pendingConfirmedUndo?.action == .redo ? "Redo" : "Undo", role: .destructive) {
                    guard let pending = pendingConfirmedUndo else { return }
                    pendingConfirmedUndo = nil
                    runRepositoryOperation(pending.action == .redo ? "Redoing Git action..." : "Undoing Git action...") {
                        await executeUndoEntry(pending.entry, menuAction: pending.action)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(pendingConfirmedUndo?.entry.confirmationMessage ?? "")
            }
            .sheet(isPresented: $showingCommitSheet) { commitSheet }
            .sheet(isPresented: $showingPullSheet) { pullSheet }
            .sheet(isPresented: $showingPushSheet) { pushSheet }
            .sheet(isPresented: $showingFetchSheet) { fetchSheet }
            .sheet(isPresented: $showingAddSubmoduleSheet) { addSubmoduleSheet }
            .sheet(isPresented: $showingAddLinkSubtreeSheet) { addLinkSubtreeSheet }
            .sheet(isPresented: $showingBranchSheet, onDismiss: { branchSheetStartPoint = nil }) { branchSheet }
            .sheet(isPresented: $showingTagSheet, onDismiss: resetTagSheet) { tagSheet }
            .sheet(isPresented: $showingNewTagSheet) { newTagSheet }
            .sheet(isPresented: tagDetailsSheetPresented) {
                if let details = displayedTagDetails {
                    TagDetailsSheet(details: details) {
                        displayedTagDetails = nil
                    }
                }
            }
            .sheet(isPresented: $showingMergeSheet) { mergeSheet }
            .sheet(isPresented: $showingStashSheet) { stashSheet }
            .sheet(isPresented: $showingRepositorySettings) { repositorySettingsSheet }
            .sheet(isPresented: createPullRequestSheetPresented) { createPullRequestSheet }
            .sheet(item: $pendingSearchFileOpenRequest) { request in
                SearchFileOpenSheet(request: request) { application, rememberChoice in
                    pendingSearchFileOpenRequest = nil
                    if rememberChoice {
                        appState.preferredSearchFileApplicationBundleIdentifier = application.bundleIdentifier
                    }
                    openSearchFile(request.relativePath, using: application)
                }
            }
            .sheet(isPresented: stashActionSheetBinding) { stashActionSheet }
            .sheet(item: $pendingCommitDropConfirmation) { confirmation in
                commitDropConfirmationSheet(for: confirmation)
            }
            .sheet(item: $pendingBranchDropConfirmation) { confirmation in
                branchDropConfirmationSheet(for: confirmation)
            }
            .sheet(item: $pendingSubtreeOperation) { pending in
                SubtreeOperationConfirmationSheet(
                    operation: pending.operation,
                    entry: pending.entry,
                    onConfirm: {
                        try await performSubtreeOperation(pending)
                    },
                    onCompleted: {
                        pendingSubtreeOperation = nil
                    },
                    onRunRepositoryOperation: runRepositoryOperation
                )
            }
            .confirmationDialog(
                "Push Branch",
                isPresented: Binding(
                    get: { pendingPushBranchDropConfirmation != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingPushBranchDropConfirmation = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Push") {
                    guard let confirmation = pendingPushBranchDropConfirmation else { return }
                    pendingPushBranchDropConfirmation = nil
                    runRepositoryOperation("Pushing \(confirmation.branch) to \(confirmation.remote)...") {
                        await performConfirmedBranchPush(confirmation)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let confirmation = pendingPushBranchDropConfirmation {
                    Text("Push \"\(confirmation.branch)\" to remote branch \"\(confirmation.remoteBranch)\"?")
                }
            }
            .sheet(isPresented: $showingRenameBranchSheet) { renameSheet }
            .sheet(isPresented: $showingCheckoutConfirmation) {
                CheckoutConfirmationSheet(branchName: branchToCheckout) { stash in
                    runRepositoryOperation("Checking out \(branchToCheckout)...") {
                        await performCheckout(ref: branchToCheckout, stash: stash)
                    }
                }
            }
            .sheet(item: $pendingRemoteBranchCheckout) { target in
                RemoteBranchCheckoutSheet(target: target) { localBranch, trackRemote in
                    runRepositoryOperation("Checking out \(localBranch)...") {
                        await performRemoteBranchCheckout(
                            target: target,
                            localBranch: localBranch,
                            trackRemote: trackRemote
                        )
                    }
                }
            }
            .alert("Confirm change working copy", isPresented: $showingDetachedHeadConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("OK") {
                    runRepositoryOperation("Checking out \(tagToCheckout)...") {
                        await performTagCheckout(tag: tagToCheckout)
                    }
                }
            } message: {
                Text("Are you sure you want to checkout '\(tagToCheckout)'?\n\nDoing so will make your working copy a 'detached HEAD', which means you won't be on a branch anymore. If you want to commit after this you'll probably want to either checkout a branch again, or create a new branch. Is this ok?")
            }
            .alert("Delete Tag", isPresented: tagDeletionConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    guard let tag = tagPendingDeletion else { return }
                    tagPendingDeletion = nil
                    runRepositoryOperation("Deleting \(tag)...") {
                        await deleteTag(tag)
                    }
                }
            } message: {
                Text("Delete local tag '\(tagPendingDeletion ?? "")'?")
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard repoSettings.refreshOnAppActive else { return }
                Task {
                    await syncState.refresh(repositoryURL: repositoryURL)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSearchModal)) { _ in
                showingSearchModal = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toolbarAction)) { notification in
                if let action = notification.userInfo?["action"] as? ToolbarAction {
                    handleToolbarAction(action)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .gitUndoAction)) { notification in
                if let action = notification.userInfo?["action"] as? GitUndoMenuAction {
                    handleGitUndoMenuAction(action)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .repositoryOperationProgressBegan)) { notification in
                if let event = notification.userInfo?["event"] as? RepositoryOperationProgressEvent {
                    operationProgress.begin(event)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .repositoryOperationProgressEnded)) { notification in
                if let id = notification.userInfo?["id"] as? UUID {
                    operationProgress.end(id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .repositoryOperationProgressCancelRequested)) { notification in
                if let id = notification.userInfo?["id"] as? UUID {
                    operationProgress.requestCancel(id)
                }
            }
    }

    private var mainContent: some View {
        ZStack {
            rootView

            if showingSearchModal {
                ZStack {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showingSearchModal = false
                        }

                    SearchModalView(
                        repositoryURL: repositoryURL,
                        initialFilter: appState.searchFilter,
                        onDismiss: { showingSearchModal = false },
                        onSelectFilter: { appState.searchFilter = $0 },
                        onSelect: { action in
                            handleSearchAction(action)
                            showingSearchModal = false
                        }
                    )
                    .padding(.top, 80)
                }
                .transition(.opacity)
            }

            if let activeOperation = operationProgress.activeOperation {
                RepositoryOperationOverlayView(
                    operation: activeOperation,
                    onCancel: { operationProgress.cancelActiveOperation() }
                )
            }

            MainWindowKeyboardHandler(showingSearchModal: $showingSearchModal)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .overlay(
            GeometryReader { geo in
                Color.clear.preference(key: WindowWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(WindowWidthKey.self) { newWidth in
            windowWidth = newWidth
        }
        .toolbar { toolbarContent }
        .navigationTitle("")
        .focusedSceneValue(\.toolbarAction, toolbarActionBinding)
        .focusedSceneValue(\.toolbarActionState, ToolbarActionState(
            isSyncing: syncState.isAnySyncing,
            stagedCount: syncState.stagedBadgeCount,
            stashableCount: syncState.stashableCount
        ))
        .frame(minWidth: 900, minHeight: 600)
        .task { await performInitialLoad() }
        .onChange(of: selectedItem) { _, newItem in
            if case .branch(let name) = newItem {
                selectedBranchName = name
            } else if case .tag(let name) = newItem {
                selectedBranchName = name
            } else if case .remoteBranch(let name) = newItem {
                selectedBranchName = name
            } else {
                selectedBranchName = nil
            }
        }
        .onDisappear {
            syncState.stopBackgroundSync()
        }
    }

    func runRepositoryOperation(_ message: String, _ operation: @escaping () async -> Void) {
        operationProgress.run(message: message, operation: operation)
    }

    @ViewBuilder
    private var rootView: some View {
        NavigationSplitView {
            sidebarPane
        } detail: {
            detailPane
        }
    }

    private var sidebarPane: some View {
        SidebarView(
            repositoryURL: repositoryURL,
            selection: $selectedItem,
            undoManager: undoManager,
            currentBranchFallbackSyncStatus: currentBranchFallbackSyncStatus,
            isBranchSyncing: { branch in
                BranchSyncBadgePolicy.shouldShowLoading(
                    for: branch,
                    isPulling: syncState.isPulling,
                    isPushing: syncState.isPushing,
                    activeSyncBranch: syncState.activeSyncBranch
                )
            },
            onRequestCheckout: { ref, isTag in
                if isTag {
                    tagToCheckout = ref
                    if repoSettings.confirmDetachedHeadCheckout {
                        showingDetachedHeadConfirmation = true
                    } else {
                        Task {
                            await performTagCheckout(tag: ref)
                        }
                    }
                } else {
                    branchToCheckout = ref
                    showingCheckoutConfirmation = true
                }
            },
            onRequestFetchBranch: { branch in
                runRepositoryOperation("Fetching \(branch)...") {
                    await syncState.performFetchAndFastForwardBranch(
                        branch: branch,
                        repositoryURL: repositoryURL,
                        credentialResolver: providerAccountController.credentialResolver()
                    )
                }
            },
            onRequestPullRemoteBranch: { remote, branch in
                runRepositoryOperation("Pulling \(remote)/\(branch)...") {
                    await syncState.performPull(
                        remote: remote,
                        branch: branch,
                        options: GitStatusService.PullOptions(),
                        repositoryURL: repositoryURL,
                        undoManager: undoManager,
                        credentialResolver: providerAccountController.credentialResolver()
                    )
                }
            },
            onRequestPullTracked: { branch in
                runRepositoryOperation("Pulling \(branch)...") {
                    await syncState.performPullBranch(
                        branch: branch,
                        repositoryURL: repositoryURL,
                        undoManager: undoManager,
                        credentialResolver: providerAccountController.credentialResolver()
                    )
                }
            },
            onRequestPushToTracked: { branch in
                runRepositoryOperation("Pushing \(branch)...") {
                    await syncState.performPushToTracked(
                        branch: branch,
                        repositoryURL: repositoryURL,
                        undoManager: undoManager
                    )
                }
            },
            onRequestRenameBranch: { branch in
                branchToRename = branch
                showingRenameBranchSheet = true
            },
            onRequestCreatePullRequest: { branch in
                runRepositoryOperation("Preparing pull request for \(branch)...") {
                    await prepareCreatePullRequest(branch: branch)
                }
            },
            onRequestCreateBranchFromBranch: { branch in
                presentBranchSheet(startPoint: .branch(branch))
            },
            onRequestCreateTagFromBranch: { branch in
                runRepositoryOperation("Preparing tag for \(branch)...") {
                    await presentTagSheetFromBranchTip(branch)
                }
            },
            onRequestTagDetails: { tag in
                runRepositoryOperation("Loading details for \(tag)...") {
                    await presentTagDetails(tag)
                }
            },
            onRequestDiffTagAgainstCurrent: { tag in
                selectedItem = .tag(tag)
                selectedBranchName = tag
            },
            onRequestPushTagToRemote: { tag, remote in
                runRepositoryOperation("Pushing \(tag) to \(remote)...") {
                    let options = GitStatusService.PushOptions(
                        remote: remote,
                        tags: [tag]
                    )
                    await syncState.performPush(
                        options: options,
                        repositoryURL: repositoryURL,
                        undoManager: undoManager,
                        credentialResolver: providerAccountController.credentialResolver()
                    )
                }
            },
            onRequestDeleteTag: { tag in
                tagPendingDeletion = tag
            },
            onRequestRebaseOnto: { branch in
                runRepositoryOperation("Rebasing onto \(branch)...") {
                    await syncState.performRebaseOnto(
                        branch: branch,
                        repositoryURL: repositoryURL,
                        undoManager: undoManager
                    )
                }
            },
            onRequestMergeBranchIntoCurrent: { branch in
                runRepositoryOperation("Merging \(branch)...") {
                    await syncState.performMerge(
                        branch: branch,
                        options: GitStatusService.MergeOptions(),
                        repositoryURL: repositoryURL
                    )
                }
            },
            onRequestPushBranchToRemote: { branch, remote in
                runRepositoryOperation("Pushing \(branch) to \(remote)...") {
                    let options = GitStatusService.PushOptions(
                        remote: remote,
                        branches: [branch],
                        branchMappings: [branch: branch]
                    )
                    await syncState.performPush(
                        options: options,
                        repositoryURL: repositoryURL,
                        undoManager: undoManager,
                        credentialResolver: providerAccountController.credentialResolver()
                    )
                }
            },
            onRequestTrackRemoteBranch: { branch, upstream in
                runRepositoryOperation(upstream == nil ? "Clearing upstream for \(branch)..." : "Tracking \(upstream!) for \(branch)...") {
                    await syncState.performTrackRemoteBranch(
                        branch: branch,
                        upstream: upstream,
                        repositoryURL: repositoryURL
                    )
                }
            },
            onRequestCreatePullRequestForRemote: { remote, branch in
                runRepositoryOperation("Preparing pull request for \(remote)/\(branch)...") {
                    await openPullRequest(remote: remote, branch: branch)
                }
            },
            onRequestApplyStash: { ref in
                requestStashAction(ref: ref, action: .apply)
            },
            onRequestDeleteStash: { ref in
                requestStashAction(ref: ref, action: .delete)
            },
            onRequestOpenWorktree: { path in
                openWorktreeInNewWindow(at: path)
            },
            onRequestOpenWorktreeInTerminal: { path in
                openWorktreeInTerminal(at: path)
            },
            onRequestOpenSubmodule: { path in
                openWorktreeInNewWindow(at: path)
            },
            onRequestShowSubmoduleInFinder: { path in
                NSWorkspace.shared.activateFileViewerSelecting([path])
            },
            onRequestOpenSubmoduleInTerminal: { path in
                openWorktreeInTerminal(at: path)
            },
            onRequestAddSubmodule: {
                showingAddSubmoduleSheet = true
            },
            onRequestAddLinkSubtree: {
                showingAddLinkSubtreeSheet = true
            },
            onRequestCreateBranch: {
                presentBranchSheet(startPoint: nil)
            },
            onRequestCreateTag: {
                showingNewTagSheet = true
            },
            onRequestShowSubtreeInFinder: { path in
                NSWorkspace.shared.activateFileViewerSelecting([path])
            },
            onRequestOpenSubtreeInTerminal: { path in
                openWorktreeInTerminal(at: path)
            },
            onRequestPullSubtree: { entry in
                pendingSubtreeOperation = PendingSubtreeOperation(operation: .pull, entry: entry)
            },
            onRequestPushSubtree: { entry in
                pendingSubtreeOperation = PendingSubtreeOperation(operation: .push, entry: entry)
            },
            onRequestUpdateSubtreeLink: { entry in
                let registry = GitSubtreeRegistry()
                try await registry.save(entry, in: repositoryURL)
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            },
            onRequestUnlinkSubtree: { entry in
                try await GitStatusService.shared.unlinkSubtree(id: entry.id, in: repositoryURL)
            },
            onRequestInitializeSubmodule: { path in
                runRepositoryOperation("Initializing \(path)...") {
                    await initializeSubmodule(at: path)
                }
            },
            onRequestUpdateSubmodule: { path, mode in
                let action = mode == .recordedCommit ? "Updating \(path) to recorded commit..." : "Updating \(path) from remote..."
                runRepositoryOperation(action) {
                    await updateSubmodule(at: path, mode: mode)
                }
            },
            onRequestSynchronizeSubmoduleURL: { path in
                runRepositoryOperation("Synchronizing \(path)...") {
                    await synchronizeSubmoduleURL(at: path)
                }
            },
            onRequestUpdateSubmoduleSettings: { path, url, branch in
                try await GitStatusService.shared.updateSubmoduleSettings(
                    path: path,
                    url: url,
                    branch: branch,
                    in: repositoryURL
                )
            },
            onRequestDeinitializeSubmodule: { path, force in
                try await GitStatusService.shared.deinitializeSubmodule(
                    path: path,
                    force: force,
                    in: repositoryURL
                )
            },
            onRequestRemoveSubmodule: { path, force in
                try await GitStatusService.shared.removeSubmodule(
                    path: path,
                    force: force,
                    in: repositoryURL
                )
            },
            onRequestSearch: {
                showingSearchModal = true
            },
            onRequestDragDrop: { request in
                handleDragDropRequest(request)
            },
            onRunRepositoryOperation: runRepositoryOperation
        )
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 600)
    }

    private var currentBranchFallbackSyncStatus: BranchSyncStatus? {
        let ahead = syncState.pushBadgeCount
        let behind = syncState.pullBadgeCount
        guard ahead > 0 || behind > 0 else { return nil }
        return BranchSyncStatus(ahead: ahead, behind: behind)
    }

    private var tagDetailsSheetPresented: Binding<Bool> {
        Binding(
            get: { displayedTagDetails != nil },
            set: { isPresented in
                if !isPresented {
                    displayedTagDetails = nil
                }
            }
        )
    }

    private var tagDeletionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { tagPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    tagPendingDeletion = nil
                }
            }
        )
    }

    @ViewBuilder
    private var detailPane: some View {
        VStack(spacing: 0) {
            Color(nsColor: .controlBackgroundColor)
                .frame(height: 1)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.separator)
                        .frame(height: 0.5)
                }

            switch selectedItem {
            case .item(.fileStatus):
                FileStatusView(
                    repositoryURL: repositoryURL,
                    syncState: syncState,
                    undoManager: undoManager,
                    onRequestApplyStash: { ref in
                        requestStashAction(ref: ref, action: .apply)
                    }
                )
            case .item(.history), .branch, .worktree, .tag, .remoteBranch, .head:
                HistoryView(
                    repositoryURL: repositoryURL,
                    selectedBranch: selectedBranchName,
                    undoManager: undoManager,
                    syncState: syncState,
                    onRunRepositoryOperation: runRepositoryOperation,
                    onRequestCheckout: { ref, isTag in
                        if isTag {
                            tagToCheckout = ref
                            if repoSettings.confirmDetachedHeadCheckout {
                                showingDetachedHeadConfirmation = true
                            } else {
                                Task {
                                    await performTagCheckout(tag: ref)
                                }
                            }
                        } else {
                            Task {
                                let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
                                if let target = remoteBranchCheckoutTarget(for: ref, remotes: remotes) {
                                    await MainActor.run {
                                        pendingRemoteBranchCheckout = target
                                    }
                                } else {
                                    await MainActor.run {
                                        branchToCheckout = ref
                                        showingCheckoutConfirmation = true
                                    }
                                }
                            }
                        }
                    }
                )
            case .item(.pullRequests):
                PullRequestListView(
                    controller: pullRequestController,
                    repositoryURL: repositoryURL,
                    accountConnectionErrorMessage: providerAccountController.errorMessage,
                    onReconnectAccount: onOpenConnections
                )
            case .stash(let ref):
                StashView(repositoryURL: repositoryURL, stashRef: ref)
            case .submodule:
                EmptyStateView(message: "Double-click to open this submodule")
            case .subtree:
                EmptyStateView(message: "Select a subtree action from the sidebar")
            case .item(.search):
                SearchView(repositoryURL: repositoryURL)
            case .none:
                EmptyStateView(message: "Select an item from the sidebar")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            leftToolbar
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Image(repoIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                Text(repositoryURL.lastPathComponent)
                    .font(.headline)
            }
            .padding(.horizontal, 12)
        }

        ToolbarItem(placement: .automatic) {
            toolbarButton(
                icon: "arrow.uturn.backward",
                label: "Undo",
                showText: appState.showToolbarButtonText,
                disabled: GitUndoToolbarPolicy.isUndoDisabled(
                    isSyncing: syncState.isAnySyncing,
                    canUndo: undoManager.canUndo
                ),
                action: { handleGitUndoMenuAction(.undo) }
            )
        }
        if appState.showHeaderRemoteButton {
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "network", label: "Remote", showText: appState.showToolbarButtonText, disabled: remoteURLString.isEmpty, action: { openRemoteURL() })
            }
        }
        if appState.showHeaderFinderButton {
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "folder", label: "Finder", showText: appState.showToolbarButtonText, action: showInFinder)
            }
        }
        if appState.showHeaderTerminalButton {
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "terminal", label: "Terminal", showText: appState.showToolbarButtonText, action: openTerminal)
            }
        }
        ToolbarItem(placement: .automatic) {
            toolbarButton(icon: "gear", label: "Settings", showText: appState.showToolbarButtonText, action: { showingRepositorySettings = true })
        }
    }

    private func performInitialLoad() async {
        async let loadedRemotes = GitStatusService.shared.remotes(in: repositoryURL)
        async let loadedCurrentBranch = GitStatusService.shared.currentBranch(in: repositoryURL)
        let (remotes, currentBranch) = await (loadedRemotes, loadedCurrentBranch)
        let loadedSettings = repoSettingsStore.settings(
            for: repositoryURL.path,
            currentBranch: currentBranch,
            remotes: remotes
        )
        await MainActor.run {
            repoSettings = loadedSettings
        }
        await syncState.refresh(repositoryURL: repositoryURL)
        syncState.startBackgroundSync(repositoryURL: repositoryURL, settings: loadedSettings)
        await refreshRemotePresentation(for: loadedSettings.defaultRemoteName)

        await MainActor.run {
            if syncState.commitBadgeCount == 0, selectedItem == .item(.fileStatus) {
                selectedItem = .item(.history)
            }
        }
    }

    @ViewBuilder
    private var leftToolbar: some View {
        let syncing = syncState.isAnySyncing
        let showText = appState.showToolbarButtonText
        if windowWidth > 1000 {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing || syncState.stagedBadgeCount == 0, showText: showText, action: { showCommitSheetIfNoConflicts() })
                BadgeToolbarButton(icon: "arrow.down.to.line", label: "Pull", badgeCount: syncState.pullBadgeCount, isLoading: syncState.isPulling, disabled: syncing, showText: showText, action: { showingPullSheet = true })
                BadgeToolbarButton(icon: "arrow.up.to.line", label: "Push", badgeCount: syncState.pushBadgeCount, isLoading: syncState.isPushing, disabled: syncing, showText: showText, action: { showingPushSheet = true })
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", showText: showText, isLoading: syncState.isFetching, disabled: syncing, action: { showingFetchSheet = true })
                if appState.showHeaderBranchButton {
                    toolbarButton(icon: "arrow.triangle.branch", label: "Branch", showText: showText, action: { presentBranchSheet(startPoint: nil) })
                }
                if appState.showHeaderMergeButton {
                    toolbarButton(icon: "arrow.triangle.merge", label: "Merge", showText: showText, isLoading: syncState.isMerging, disabled: syncing, action: { showingMergeSheet = true })
                }
                if appState.showHeaderStashButton {
                    toolbarButton(icon: "archivebox", label: "Stash", showText: showText, isLoading: syncState.isStashing, disabled: syncing || syncState.stashableCount == 0, action: { showingStashSheet = true })
                }
            }
        } else if windowWidth > 800 {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing || syncState.stagedBadgeCount == 0, showText: showText, action: { showCommitSheetIfNoConflicts() })
                BadgeToolbarButton(icon: "arrow.down.to.line", label: "Pull", badgeCount: syncState.pullBadgeCount, isLoading: syncState.isPulling, disabled: syncing, showText: showText, action: { showingPullSheet = true })
                BadgeToolbarButton(icon: "arrow.up.to.line", label: "Push", badgeCount: syncState.pushBadgeCount, isLoading: syncState.isPushing, disabled: syncing, showText: showText, action: { showingPushSheet = true })
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", showText: showText, isLoading: syncState.isFetching, disabled: syncing, action: { showingFetchSheet = true })
                moreMenu
            }
        } else {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing || syncState.stagedBadgeCount == 0, showText: showText, action: { showCommitSheetIfNoConflicts() })
                moreMenu
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            let syncing = syncState.isAnySyncing
            if windowWidth <= 800 {
                Button("Pull") { showingPullSheet = true }
                    .disabled(syncing)
                Button("Push") { showingPushSheet = true }
                    .disabled(syncing)
                Button("Fetch") { showingFetchSheet = true }
                    .disabled(syncing)
            }
            if windowWidth <= 1000 {
                if appState.showHeaderBranchButton {
                    Button("Branch") { presentBranchSheet(startPoint: nil) }
                }
                if appState.showHeaderMergeButton {
                    Button("Merge") { showingMergeSheet = true }
                        .disabled(syncing)
                }
                if appState.showHeaderStashButton {
                    Button("Stash", action: { showingStashSheet = true })
                        .disabled(syncing || syncState.stashableCount == 0)
                }
            }
        } label: {
            ToolbarButtonLabel(icon: "ellipsis", label: "More", showText: appState.showToolbarButtonText)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("More Actions")
    }

    func showCommitSheetIfNoConflicts() {
        Task {
            if await syncState.checkConflicts(repositoryURL: repositoryURL) { return }
            showingCommitSheet = true
        }
    }

    func commitFromToolbar(message: String) async {
        await syncState.performCommit(
            message: message,
            repositoryURL: repositoryURL,
            undoManager: undoManager
        )
    }

    func performCommitDropCherryPick(_ confirmation: PendingCommitDropConfirmation) async {
        guard !syncState.isAnySyncing else {
            await MainActor.run {
                syncState.showInfo("Wait for the current Git operation to finish before dragging commits.")
            }
            return
        }

        let hashes = confirmation.commits.map(\.hash)
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        guard currentBranch == confirmation.targetBranch else {
            await MainActor.run {
                syncState.showInfo("The HEAD branch changed. Repeat the drag and drop action.")
            }
            return
        }

        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.cherryPickCommits(hashes, in: repositoryURL)
            await registerHeadChangingUndo(
                label: hashes.count == 1 ? "Cherry-pick \(confirmation.commits[0].hash.prefix(7))" : "Cherry-pick \(hashes.count) commits",
                oldHead: oldHead,
                redoOperation: .cherryPickCommits(commits: hashes)
            )
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await syncState.refresh(repositoryURL: repositoryURL)
            let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
            let inProgress = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
            await MainActor.run {
                if hasConflicts {
                    selectedItem = .item(.fileStatus)
                    syncState.showError("Cherry-pick produced conflicts. Resolve them in the File status view, then continue or abort.")
                } else if inProgress != nil {
                    selectedItem = .item(.fileStatus)
                    syncState.showError("Cherry-pick produced an empty commit. Open the File status view to skip or abort.")
                } else {
                    syncState.showError(error.localizedDescription)
                }
            }
        }
    }

    func performBranchDropOperation(_ confirmation: PendingBranchDropConfirmation) async {
        guard !syncState.isAnySyncing, !isPerformingBranchDropOperation else {
            await MainActor.run {
                syncState.showInfo("Wait for the current Git operation to finish before dragging branches.")
            }
            return
        }

        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        guard currentBranch == confirmation.targetBranch else {
            await MainActor.run {
                syncState.showInfo("The current branch changed. Repeat the drag and drop action.")
            }
            return
        }

        guard confirmation.sourceBranch != confirmation.targetBranch else {
            await MainActor.run {
                syncState.showInfo("Drop a different branch onto the current branch.")
            }
            return
        }

        if await GitStatusService.shared.hasConflicts(in: repositoryURL) {
            await MainActor.run {
                selectedItem = .item(.fileStatus)
                syncState.showConflict("There are unresolved merge conflicts. Please resolve them before proceeding.")
            }
            return
        }

        let inProgressOperation = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
        guard inProgressOperation == nil else {
            await MainActor.run {
                syncState.showInfo("Finish the current Git operation before dragging branches.")
            }
            return
        }

        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)

        await MainActor.run {
            isPerformingBranchDropOperation = true
        }
        defer {
            Task { @MainActor in
                isPerformingBranchDropOperation = false
            }
        }

        do {
            switch confirmation.operation {
            case .merge:
                try await GitStatusService.shared.mergeCommit(
                    confirmation.sourceBranch,
                    noCommit: false,
                    log: false,
                    in: repositoryURL
                )
            case .rebase:
                try await GitStatusService.shared.rebaseCommit(
                    confirmation.sourceBranch,
                    in: repositoryURL
                )
            }

            await registerHeadChangingUndo(
                label: confirmation.operation == .merge
                    ? "Merge \(confirmation.sourceBranch)"
                    : "Rebase onto \(confirmation.sourceBranch)",
                oldHead: oldHead,
                redoOperation: confirmation.operation == .merge
                    ? .mergeCommit(commit: confirmation.sourceBranch, noCommit: false, log: false)
                    : .rebaseOnto(commit: confirmation.sourceBranch)
            )
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )

            let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
            let inProgressAfterFailure = await GitStatusService.shared.inProgressOperation(in: repositoryURL)

            await MainActor.run {
                if hasConflicts || inProgressAfterFailure != nil {
                    selectedItem = .item(.fileStatus)
                    syncState.showConflict(
                        confirmation.operation == .merge
                            ? "Merge conflicts occurred during Merge. Please resolve them in the File status view."
                            : "Rebase conflicts occurred during Rebase. Please resolve them in the File status view."
                    )
                } else {
                    syncState.showError(error.localizedDescription)
                }
            }
        }
    }

    private func registerHeadChangingUndo(
        label: String,
        oldHead: String?,
        redoOperation: GitUndoOperation
    ) async {
        guard let oldHead,
              let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
              oldHead != newHead else { return }

        await MainActor.run {
            undoManager.register(
                GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: label,
                    undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                    redoOperation: redoOperation
                )
            )
        }
    }

    func requestStashAction(ref: String, action: StashAction) {
        if action == .delete && !repoSettings.confirmDestructiveStashActions {
            Task {
                await performStashAction(ref: ref, action: action, deleteAfterApplying: false)
            }
            return
        }
        pendingStashRef = ref
        pendingStashAction = action
    }

    private var stashActionSheetBinding: Binding<Bool> {
        Binding(
            get: { pendingStashRef != nil && pendingStashAction != nil },
            set: { isPresented in
                if !isPresented {
                    clearPendingStashAction()
                }
            }
        )
    }

    @MainActor
    private func clearPendingStashAction() {
        pendingStashRef = nil
        pendingStashAction = nil
    }

    func performStashAction(ref: String, action: StashAction, deleteAfterApplying: Bool) async {
        do {
            switch action {
            case .apply:
                let support = GitStashUndoSupport()
                let canRegisterUndo = await canRegisterStashApplyUndo(ref: ref)
                let head = canRegisterUndo ? await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL) : nil
                let hash = canRegisterUndo ? try await support.hash(for: ref, in: repositoryURL) : nil
                let summary = canRegisterUndo ? try await support.summary(for: ref, in: repositoryURL) : nil
                try await GitStatusService.shared.applyStash(
                    ref: ref,
                    dropAfterApplying: deleteAfterApplying,
                    in: repositoryURL
                )
                if canRegisterUndo, let head, let hash, let summary {
                    let undoOperation: GitUndoOperation
                    if deleteAfterApplying {
                        undoOperation = .sequence([
                            .resetHardToHead(expectedHead: head),
                            .stashStore(commit: hash, message: summary)
                        ])
                    } else {
                        undoOperation = .resetHardToHead(expectedHead: head)
                    }
                    await MainActor.run {
                        undoManager.register(
                            GitUndoEntry(
                                repositoryURL: repositoryURL,
                                label: deleteAfterApplying ? "Pop stash" : "Apply stash",
                                undoOperation: undoOperation,
                                redoOperation: deleteAfterApplying ? .stashPop(ref: ref) : .stashApply(ref: hash)
                            )
                        )
                    }
                }
            case .delete:
                let support = GitStashUndoSupport()
                let hash = try await support.hash(for: ref, in: repositoryURL)
                let summary = try await support.summary(for: ref, in: repositoryURL)
                try await GitStatusService.shared.dropStash(ref: ref, in: repositoryURL)
                await MainActor.run {
                    undoManager.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Drop stash",
                            undoOperation: .stashStore(commit: hash, message: summary),
                            redoOperation: .stashDropMatchingHash(hash: hash)
                        )
                    )
                }
            }
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            syncState.showError(error.localizedDescription)
        }

        await MainActor.run {
            clearPendingStashAction()
        }
    }

    private func canRegisterStashApplyUndo(ref: String) async -> Bool {
        let support = GitStashUndoSupport()
        do {
            let clean = try await support.isWorkingTreeClean(in: repositoryURL)
            let hasUntrackedPayload = try await support.stashHasUntrackedPayload(ref: ref, in: repositoryURL)
            if !clean || hasUntrackedPayload {
                await MainActor.run {
                    syncState.showInfo("Stash action completed without undo because the working tree or stash payload is not clean enough for a safe reset.")
                }
                return false
            }
            return true
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
            return false
        }
    }

    func openRemoteURL(remote: String? = nil) {
        if let remote {
            Task {
                let remoteValue = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
                guard let url = browserURL(from: remoteValue) else {
                    _ = await MainActor.run {
                        syncState.showInfo("Could not find a remote URL for '\(remote)'.")
                    }
                    return
                }
                _ = await MainActor.run {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        guard let url = browserURL(from: remoteURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func showInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repositoryURL.path)
    }

    private func openTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", repositoryURL.path]
        do {
            try process.run()
        } catch {
            print("Failed to open Terminal: \(error)")
        }
    }

    private func openWorktreeInNewWindow(at path: URL) {
        appState.newWindowRepoURL = path
        openWindow(id: "main")
    }

    private func openWorktreeInTerminal(at path: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path.path]
        do {
            try process.run()
        } catch {
            print("Failed to open Terminal for worktree: \(error)")
        }
    }

    func openGitIgnoreFile() {
        do {
            let fileURL = try fileService.prepareGitIgnore(in: repositoryURL)
            NSWorkspace.shared.open(fileURL)
        } catch {
            syncState.showError(error.localizedDescription)
        }
    }

    func openGitConfigFile() {
        guard let fileURL = fileService.gitConfigURL(in: repositoryURL) else {
            syncState.showInfo("Could not find .git/config for this repository.")
            return
        }
        NSWorkspace.shared.open(fileURL)
    }

    func refreshRemotePresentation(for preferredRemote: String?) async {
        let fallbackRemote = await GitStatusService.shared.remotes(in: repositoryURL).first
        let remote = preferredRemote ?? fallbackRemote
        guard let remote else {
            await MainActor.run {
                remoteURLString = ""
                repoIconName = "code-branch"
            }
            return
        }

        let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        await MainActor.run {
            remoteURLString = remoteURL
            repoIconName = remoteURL.isEmpty ? "code-branch" : determineRepoIconName(from: remoteURL)
        }
    }

    func resolvedPullPreselectedBranch() -> String? {
        if repoSettings.defaultPullBranch.isEmpty {
            return pullPreselectedBranch
        }
        return repoSettings.defaultPullBranch
    }

    func presentTagSheetFromBranchTip(_ sourceBranch: String) async {
        let commits = await GitStatusService.shared.commitHistory(
            branch: sourceBranch,
            limit: 1,
            in: repositoryURL
        )

        await MainActor.run {
            if let commit = commits.first {
                branchTagStartPoint = BranchTagStartPoint(
                    branchName: sourceBranch,
                    hash: commit.hash,
                    message: commit.message
                )
                showingTagSheet = true
            } else {
                syncState.showError("Could not find the last commit for \(sourceBranch).")
            }
        }
    }

    func createTagFromBranch() async {
        guard let startPoint = branchTagStartPoint else { return }
        let name = tagNameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        do {
            try await GitStatusService.shared.createTag(
                name: name,
                commit: startPoint.hash,
                annotated: false,
                message: nil,
                in: repositoryURL
            )
            await MainActor.run {
                showingTagSheet = false
            }
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func createTag(from request: TagCreationRequest) async throws {
        try await GitStatusService.shared.createTag(
            name: request.name,
            commit: request.commitReference,
            annotated: false,
            message: nil,
            in: repositoryURL
        )

        if let remote = request.pushRemote {
            _ = try await GitStatusService.shared.push(
                options: GitStatusService.PushOptions(remote: remote, tags: [request.name]),
                in: repositoryURL,
                credentialResolver: providerAccountController.credentialResolver()
            )
        }

        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }

    private func presentTagDetails(_ tag: String) async {
        do {
            let details = try await GitStatusService.shared.tagDetails(
                name: tag,
                in: repositoryURL
            )
            await MainActor.run {
                displayedTagDetails = details
            }
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    private func deleteTag(_ tag: String) async {
        do {
            try await GitStatusService.shared.deleteTag(name: tag, in: repositoryURL)
            await MainActor.run {
                if selectedItem == .tag(tag) {
                    selectedItem = .item(.history)
                }
            }
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    private func resetTagSheet() {
        tagNameInput = ""
        branchTagStartPoint = nil
    }

}
