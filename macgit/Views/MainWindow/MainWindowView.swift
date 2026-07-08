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

private struct PendingCommitDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let commits: [GitDraggedCommit]
    let targetBranch: String
}

private struct PendingBranchDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let sourceBranch: String
    let targetBranch: String
    var operation: GitDragBranchOperation
}

private struct PendingPushBranchDropConfirmation: Identifiable, Equatable {
    let id = UUID()
    let branch: String
    let remote: String

    var remoteBranch: String {
        "\(remote)/\(branch)"
    }
}

private struct BranchTagStartPoint: Equatable {
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    private let repoSettingsStore = RepoSettingsStore.shared
    private let fileService = RepositorySettingsFileService()
    private let undoExecutor = GitUndoExecutor()
    @State private var selectedItem: SidebarSelection? = .item(.fileStatus)
    @State private var windowWidth: CGFloat = 0
    @State private var showingCommitSheet = false
    @State private var showingPullSheet = false
    @State private var showingPushSheet = false
    @State private var showingFetchSheet = false
    @State private var showingBranchSheet = false
    @State private var branchSheetStartPoint: GitBranchStartPoint?
    @State private var showingTagSheet = false
    @State private var tagNameInput = ""
    @State private var branchTagStartPoint: BranchTagStartPoint?
    @State private var showingMergeSheet = false
    @State private var showingStashSheet = false
    @State private var showingCheckoutConfirmation = false
    @State private var branchToCheckout: String = ""
    @State private var showingRenameBranchSheet = false
    @State private var branchToRename: String = ""
    @State private var showingDetachedHeadConfirmation = false
    @State private var tagToCheckout: String = ""
    @State private var pendingStashRef: String?
    @State private var pendingStashAction: StashAction?
    @State private var pendingStashPaths: [String] = []
    @StateObject private var syncState = SyncState()
    @StateObject private var undoManager = GitUndoManager()
    @StateObject private var pullRequestController: PullRequestController
    @State private var repoIconName: String = "code-branch"
    @State private var remoteURLString: String = ""
    @State private var selectedBranchName: String? = nil
    @State private var pullPreselectedBranch: String? = nil
    @State private var showingSearchModal = false
    @State private var showingRepositorySettings = false
    @State private var pendingSearchFileOpenRequest: SearchFileOpenRequest?
    @State private var repoSettings = RepoSettings.defaults(currentBranch: nil, remotes: [])
    @State private var pendingConfirmedUndo: (entry: GitUndoEntry, action: GitUndoMenuAction)?
    @State private var pendingCommitDropConfirmation: PendingCommitDropConfirmation?
    @State private var pendingBranchDropConfirmation: PendingBranchDropConfirmation?
    @State private var pendingPushBranchDropConfirmation: PendingPushBranchDropConfirmation?
    @State private var isPerformingBranchDropOperation = false
    @StateObject private var operationProgress = RepositoryOperationProgress()

    init(repositoryURL: URL, providerAccountController: GitProviderAccountController) {
        self.repositoryURL = repositoryURL
        self.providerAccountController = providerAccountController
        _pullRequestController = StateObject(wrappedValue: PullRequestController(
            providerAccountController: providerAccountController,
            tokenVault: KeychainGitProviderTokenVault(),
            services: [.github: GitHubPullRequestService()],
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
            .sheet(isPresented: $showingBranchSheet, onDismiss: { branchSheetStartPoint = nil }) { branchSheet }
            .sheet(isPresented: $showingTagSheet, onDismiss: resetTagSheet) { tagSheet }
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

    private func runRepositoryOperation(_ message: String, _ operation: @escaping () async -> Void) {
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
                    await syncState.performFetchBranch(
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
                    onRunRepositoryOperation: runRepositoryOperation
                )
            case .item(.pullRequests):
                PullRequestListView(
                    controller: pullRequestController,
                    repositoryURL: repositoryURL,
                    onConnectAccount: {
                        Task { await providerAccountController.connectGitHub() }
                    }
                )
            case .stash(let ref):
                StashView(repositoryURL: repositoryURL, stashRef: ref)
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

    @ViewBuilder
    private var commitSheet: some View {
        CommitSheetView { message in
            runRepositoryOperation("Committing changes...") {
                await commitFromToolbar(message: message)
            }
        }
    }

    @ViewBuilder
    private var pullSheet: some View {
        PullSheetView(
            repositoryURL: repositoryURL,
            preselectedRemote: repoSettings.defaultRemoteName,
            preselectedBranch: resolvedPullPreselectedBranch(),
            defaultPullStrategy: repoSettings.pullStrategy
        ) { remote, branch, options in
            runRepositoryOperation("Pulling \(remote)/\(branch)...") {
                await syncState.performPull(
                    remote: remote,
                    branch: branch,
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    credentialResolver: providerAccountController.credentialResolver()
                )
            }
        }
    }

    @ViewBuilder
    private var pushSheet: some View {
        PushSheetView(repositoryURL: repositoryURL) { options in
            runRepositoryOperation("Pushing branches...") {
                await syncState.performPush(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager,
                    credentialResolver: providerAccountController.credentialResolver()
                )
            }
        }
    }

    @ViewBuilder
    private var fetchSheet: some View {
        FetchSheetView(repositoryURL: repositoryURL) { options in
            runRepositoryOperation("Fetching remotes...") {
                await syncState.performFetch(
                    options: options,
                    repositoryURL: repositoryURL,
                    credentialResolver: providerAccountController.credentialResolver()
                )
            }
        }
    }

    @ViewBuilder
    private var branchSheet: some View {
        BranchSheetView(
            repositoryURL: repositoryURL,
            undoManager: undoManager,
            initialStartPoint: branchSheetStartPoint,
            onRunRepositoryOperation: runRepositoryOperation,
            onCompleted: {
                Task {
                    await syncState.refresh(repositoryURL: repositoryURL)
                    NotificationCenter.default.post(
                        name: .repositoryDidChange,
                        object: nil,
                        userInfo: ["repositoryURL": repositoryURL]
                    )
                }
            }
        )
    }

    @ViewBuilder
    private var tagSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Tag")
                .font(.title2)
                .fontWeight(.semibold)

            if let startPoint = branchTagStartPoint {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From branch:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("\(startPoint.branchName) at \(startPoint.shortHash) : \(startPoint.message)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tag name:")
                    .font(.system(size: 13))
                TextField("Enter tag name...", text: $tagNameInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingTagSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create Tag") {
                    Task { await createTagFromBranch() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagNameInput.trimmingCharacters(in: .whitespaces).isEmpty || branchTagStartPoint == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }

    @ViewBuilder
    private var renameSheet: some View {
        RenameBranchSheetView(
            repositoryURL: repositoryURL,
            currentName: branchToRename,
            undoManager: undoManager,
            onRunRepositoryOperation: runRepositoryOperation,
            onCompleted: {
                Task {
                    await syncState.refresh(repositoryURL: repositoryURL)
                    NotificationCenter.default.post(
                        name: .repositoryDidChange,
                        object: nil,
                        userInfo: ["repositoryURL": repositoryURL]
                    )
                }
            }
        )
    }

    @ViewBuilder
    private func commitDropConfirmationSheet(
        for confirmation: PendingCommitDropConfirmation
    ) -> some View {
        GitDragActionConfirmationSheet(
            title: "Cherry-pick Commits",
            message: "Cherry-pick the selected commits into the current HEAD branch.",
            targetBranchName: confirmation.targetBranch,
            commits: confirmation.commits,
            primaryActionTitle: "Cherry-pick",
            onConfirm: {
                let request = confirmation
                pendingCommitDropConfirmation = nil
                runRepositoryOperation("Cherry-picking commits...") {
                    await performCommitDropCherryPick(request)
                }
            },
            onCancel: {
                pendingCommitDropConfirmation = nil
            }
        )
    }

    @ViewBuilder
    private func branchDropConfirmationSheet(
        for confirmation: PendingBranchDropConfirmation
    ) -> some View {
        GitDragActionConfirmationSheet(
            title: "Merge or Rebase Branch",
            message: "Review the branch action before continuing.",
            sourceBranchName: confirmation.sourceBranch,
            targetBranchName: confirmation.targetBranch,
            commits: [],
            primaryActionTitle: "Continue",
            selectedBranchOperation: Binding(
                get: { pendingBranchDropConfirmation?.operation ?? confirmation.operation },
                set: { newValue in
                    guard var pending = pendingBranchDropConfirmation else { return }
                    pending.operation = newValue
                    pendingBranchDropConfirmation = pending
                }
            ),
            onConfirm: {
                guard let request = pendingBranchDropConfirmation else { return }
                pendingBranchDropConfirmation = nil
                runRepositoryOperation(request.operation == .merge ? "Merging \(request.sourceBranch)..." : "Rebasing onto \(request.sourceBranch)...") {
                    await performBranchDropOperation(request)
                }
            },
            onCancel: {
                pendingBranchDropConfirmation = nil
            }
        )
    }

    @ViewBuilder
    private var mergeSheet: some View {
        MergeSheetView(repositoryURL: repositoryURL) { branch, message, options in
            runRepositoryOperation("Merging \(branch)...") {
                await syncState.performMerge(branch: branch, options: options, repositoryURL: repositoryURL)
            }
        }
    }

    @ViewBuilder
    private var stashSheet: some View {
        StashSheetView(paths: pendingStashPaths) { options in
            let pathsToStash = options.paths
            runRepositoryOperation(pathsToStash.isEmpty ? "Stashing changes..." : "Stashing \(pathsToStash.count) files...") {
                await syncState.performStash(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager
                )
            }
            clearPendingStashPaths()
        }
        .onDisappear {
            clearPendingStashPaths()
        }
    }

    @MainActor
    private func clearPendingStashPaths() {
        guard !pendingStashPaths.isEmpty else { return }
        pendingStashPaths = []
    }

    @ViewBuilder
    private var stashActionSheet: some View {
        if let ref = pendingStashRef, let action = pendingStashAction {
            StashActionConfirmationSheet(stashRef: ref, action: action) { deleteAfterApplying in
                runRepositoryOperation(action == .apply ? "Applying \(ref)..." : "Deleting \(ref)...") {
                    await performStashAction(
                        ref: ref,
                        action: action,
                        deleteAfterApplying: deleteAfterApplying
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var repositorySettingsSheet: some View {
        RepositorySettingsSheetView(
            repositoryURL: repositoryURL,
            initialSettings: repoSettings,
            onSave: { newSettings in
                repoSettings = newSettings
                repoSettingsStore.update(for: repositoryURL.path, settings: newSettings)
                syncState.startBackgroundSync(repositoryURL: repositoryURL, settings: newSettings)
                Task {
                    await refreshRemotePresentation(for: newSettings.defaultRemoteName)
                }
            },
            onOpenGitIgnore: openGitIgnoreFile,
            onOpenGitConfig: openGitConfigFile,
            onOpenRemoteURL: { remote in
                openRemoteURL(remote: remote)
            }
        )
    }

    private var createPullRequestSheetPresented: Binding<Bool> {
        Binding(
            get: { pullRequestController.createDraftSeed != nil },
            set: { isPresented in
                if !isPresented {
                    pullRequestController.dismissCreatePullRequest()
                }
            }
        )
    }

    @ViewBuilder
    private var createPullRequestSheet: some View {
        if let seed = pullRequestController.createDraftSeed {
            CreatePullRequestSheet(
                seed: seed,
                isSubmitting: pullRequestController.isPerformingAction,
                onCancel: { pullRequestController.dismissCreatePullRequest() },
                onCreate: { draft in
                    Task { await pullRequestController.createPullRequest(draft) }
                }
            )
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

    private func showCommitSheetIfNoConflicts() {
        Task {
            if await syncState.checkConflicts(repositoryURL: repositoryURL) { return }
            showingCommitSheet = true
        }
    }

    private func commitFromToolbar(message: String) async {
        await syncState.performCommit(
            message: message,
            repositoryURL: repositoryURL,
            undoManager: undoManager
        )
    }

    private func performCheckout(ref: String, stash: Bool) async {
        do {
            let support = GitBranchUndoSupport()
            let previousRef = try await support.currentRef(in: repositoryURL)
            if stash {
                try await GitStatusService.shared.stash(
                    options: GitStatusService.StashOptions(
                        message: "Stashed before switching to \(ref)",
                        keepIndex: false
                    ),
                    in: repositoryURL
                )
            }
            try await GitStatusService.shared.checkoutCommit(ref, in: repositoryURL)
            await MainActor.run {
                undoManager.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Checkout \(ref)",
                        undoOperation: .checkoutRef(ref: previousRef),
                        redoOperation: .checkoutRef(ref: ref)
                    )
                )
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
    }

    private func performTagCheckout(tag: String) async {
        await performCheckout(ref: tag, stash: false)
    }

    private func performCommitDropCherryPick(_ confirmation: PendingCommitDropConfirmation) async {
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

    private func performBranchDropOperation(_ confirmation: PendingBranchDropConfirmation) async {
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

    private func requestStashAction(ref: String, action: StashAction) {
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

    private func performStashAction(ref: String, action: StashAction, deleteAfterApplying: Bool) async {
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

    private func openRemoteURL(remote: String? = nil) {
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

    private func openPullRequest(branch: String) async {
        guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
            await MainActor.run {
                syncState.showError("Branch '\(branch)' has no upstream. Push it first to create a pull request.")
            }
            return
        }
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else {
            await MainActor.run {
                syncState.showError("Could not parse upstream '\(upstream)'.")
            }
            return
        }
        let remoteName = parts[0]
        let remoteBranch = parts[1]
        let remoteURL = await GitStatusService.shared.remoteURL(remote: remoteName, in: repositoryURL)
        guard let url = PullRequestURLBuilder.build(remoteURL: remoteURL, branch: remoteBranch) else {
            await MainActor.run {
                syncState.showError("Remote '\(remoteName)' is not a recognized pull request host (GitHub, GitLab, or Bitbucket).")
            }
            return
        }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    private func prepareCreatePullRequest(branch: String) async {
        do {
            let remote = try await prepareRemoteBranchForPullRequest(branch: branch)
            await pullRequestController.loadPullRequests(repositoryURL: repositoryURL, remoteName: remote)
            if let errorMessage = pullRequestController.errorMessage {
                await MainActor.run {
                    syncState.showError(errorMessage)
                }
                return
            }
            await pullRequestController.presentCreatePullRequest(sourceBranch: branch)
            if pullRequestController.createDraftSeed == nil,
               let detailErrorMessage = pullRequestController.detailErrorMessage {
                await MainActor.run {
                    syncState.showError(detailErrorMessage)
                    pullRequestController.detailErrorMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    private func prepareRemoteBranchForPullRequest(branch: String) async throws -> String {
        let localBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localBranch.isEmpty else {
            throw GitError.commandFailed("Branch name is required.")
        }

        if let upstream = await GitStatusService.shared.upstreamBranch(for: localBranch, in: repositoryURL) {
            let remoteBranch = try parseRemoteBranch(upstream)
            if let status = await GitStatusService.shared.branchSyncStatus(for: localBranch, in: repositoryURL) {
                if status.behind > 0 {
                    throw GitError.commandFailed("Branch '\(localBranch)' is behind '\(upstream)'. Pull or rebase it before creating a pull request.")
                }
                if status.ahead > 0 {
                    try await pushBranchForPullRequest(
                        localBranch: localBranch,
                        remote: remoteBranch.remote,
                        remoteBranch: remoteBranch.branch,
                        setUpstream: false
                    )
                }
            }
            return remoteBranch.remote
        }

        let remote = try await defaultPullRequestRemote()
        try await pushBranchForPullRequest(
            localBranch: localBranch,
            remote: remote,
            remoteBranch: localBranch,
            setUpstream: true
        )
        return remote
    }

    private func defaultPullRequestRemote() async throws -> String {
        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        guard !remotes.isEmpty else {
            throw GitError.commandFailed("No remotes configured. Add a remote before creating a pull request.")
        }
        if let preferred = repoSettings.defaultRemoteName,
           remotes.contains(preferred) {
            return preferred
        }
        return remotes.first(where: { $0 == "origin" }) ?? remotes[0]
    }

    private func parseRemoteBranch(_ upstream: String) throws -> (remote: String, branch: String) {
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw GitError.commandFailed("Could not parse upstream '\(upstream)'.")
        }
        return (parts[0], parts[1])
    }

    private func pushBranchForPullRequest(
        localBranch: String,
        remote: String,
        remoteBranch: String,
        setUpstream: Bool
    ) async throws {
        await MainActor.run {
            syncState.isPushing = true
            syncState.activeSyncBranch = localBranch
        }
        defer {
            Task { @MainActor in
                syncState.isPushing = false
                syncState.activeSyncBranch = nil
            }
        }

        let options = GitStatusService.PushOptions(
            remote: remote,
            branches: [localBranch],
            branchMappings: [localBranch: remoteBranch]
        )
        _ = try await GitStatusService.shared.push(
            options: options,
            in: repositoryURL,
            credentialResolver: providerAccountController.credentialResolver()
        )
        if setUpstream {
            try await GitStatusService.shared.setUpstream(
                upstream: "\(remote)/\(remoteBranch)",
                branch: localBranch,
                in: repositoryURL
            )
        }
        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }

    private func openPullRequest(remote: String, branch: String) async {
        let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        guard let url = PullRequestURLBuilder.build(remoteURL: remoteURL, branch: branch) else {
            await MainActor.run {
                syncState.showError("Remote '\(remote)' is not a recognized pull request host (GitHub, GitLab, or Bitbucket).")
            }
            return
        }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
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

    private func openGitIgnoreFile() {
        do {
            let fileURL = try fileService.prepareGitIgnore(in: repositoryURL)
            NSWorkspace.shared.open(fileURL)
        } catch {
            syncState.showError(error.localizedDescription)
        }
    }

    private func openGitConfigFile() {
        guard let fileURL = fileService.gitConfigURL(in: repositoryURL) else {
            syncState.showInfo("Could not find .git/config for this repository.")
            return
        }
        NSWorkspace.shared.open(fileURL)
    }

    private func refreshRemotePresentation(for preferredRemote: String?) async {
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

    private func resolvedPullPreselectedBranch() -> String? {
        if repoSettings.defaultPullBranch.isEmpty {
            return pullPreselectedBranch
        }
        return repoSettings.defaultPullBranch
    }

    private func browserURL(from remoteURLString: String) -> URL? {
        var cleaned = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Convert SSH URL format: git@host:user/repo.git -> https://host/user/repo.git
        if cleaned.hasPrefix("git@") {
            let withoutPrefix = cleaned.dropFirst("git@".count)
            if let colonIndex = withoutPrefix.firstIndex(of: ":") {
                let host = withoutPrefix[..<colonIndex]
                let path = withoutPrefix[withoutPrefix.index(after: colonIndex)...]
                cleaned = "https://\(host)/\(path)"
            }
        }

        // Convert ssh:// format: ssh://git@host/user/repo.git -> https://host/user/repo.git
        if cleaned.hasPrefix("ssh://") {
            cleaned = String(cleaned.dropFirst("ssh://".count))
            if cleaned.hasPrefix("git@") {
                cleaned = String(cleaned.dropFirst("git@".count))
            }
            cleaned = "https://\(cleaned)"
        }

        // Remove .git suffix
        if cleaned.hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(".git".count))
        }

        return URL(string: cleaned)
    }

    private var toolbarActionBinding: Binding<ToolbarAction> {
        Binding(
            get: { .commit },
            set: { newValue in
                handleToolbarAction(newValue)
            }
        )
    }

    private func handleToolbarAction(_ action: ToolbarAction) {
        let syncing = syncState.isAnySyncing
        switch action {
        case .commit:
            if !syncing && syncState.stagedBadgeCount > 0 {
                showCommitSheetIfNoConflicts()
            }
        case .pull:
            if !syncing { showingPullSheet = true }
        case .push:
            if !syncing { showingPushSheet = true }
        case .fetch:
            if !syncing { showingFetchSheet = true }
        case .branch:
            presentBranchSheet(startPoint: nil)
        case .merge:
            if !syncing { showingMergeSheet = true }
        case .stash:
            if !syncing && syncState.stashableCount > 0 {
                showingStashSheet = true
            }
        case .search:
            showingSearchModal = true
        }
    }

    private func handleGitUndoMenuAction(_ action: GitUndoMenuAction) {
        guard !syncState.isAnySyncing else {
            syncState.showInfo("Wait for the current Git operation to finish before undoing.")
            return
        }
        guard pendingConfirmedUndo == nil else { return }

        switch action {
        case .undo:
            guard let entry = undoManager.popForUndo() else {
                syncState.showInfo("Nothing to undo.")
                return
            }
            if entry.confirmationMessage?.isEmpty == false {
                pendingConfirmedUndo = (entry, action)
                return
            }
            Task {
                await executeUndoEntry(entry, menuAction: .undo)
            }
        case .redo:
            guard let entry = undoManager.popForRedo() else {
                syncState.showInfo("Nothing to redo.")
                return
            }
            if entry.confirmationMessage?.isEmpty == false {
                pendingConfirmedUndo = (entry, action)
                return
            }
            Task {
                await executeUndoEntry(entry, menuAction: .redo)
            }
        }
    }

    private func handleDragDropRequest(_ request: GitDragDropRequest) {
        switch request {
        case .cherryPick(let commits, let targetBranch):
            pendingCommitDropConfirmation = PendingCommitDropConfirmation(
                commits: commits,
                targetBranch: targetBranch
            )
        case .branchOperation(let source, let target, let operation):
            pendingBranchDropConfirmation = PendingBranchDropConfirmation(
                sourceBranch: source,
                targetBranch: target,
                operation: operation
            )
        case .createBranch(let startPoint):
            presentCreateBranchSheet(startPoint: startPoint)
        case .checkoutRemoteBranch(let fullPath):
            runRepositoryOperation("Checking out \(fullPath)...") {
                await checkoutRemoteBranchFromDrop(fullPath)
            }
        case .createTagFromBranch(let sourceBranch):
            Task {
                await presentTagSheetFromBranchTip(sourceBranch)
            }
        case .pushBranchToRemote(let branch):
            Task {
                await presentPushBranchDropConfirmation(branch)
            }
        case .stashFiles(let paths):
            handleStashFilesDrop(paths: paths)
        case .applyStash(let ref):
            requestStashAction(ref: ref, action: .apply)
        }
    }

    private func handleStashFilesDrop(paths: [String]) {
        guard !paths.isEmpty else { return }
        if syncState.isAnySyncing {
            syncState.showInfo("Wait for the current operation to finish before stashing more files.")
            return
        }
        pendingStashPaths = paths
        showingStashSheet = true
    }

    private func checkoutRemoteBranchFromDrop(_ fullPath: String) async {
        let parts = fullPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            await MainActor.run {
                syncState.showError("Could not parse remote branch '\(fullPath)'.")
            }
            return
        }

        let remote = String(parts[0])
        let branch = String(parts[1])
        guard !remote.isEmpty, !branch.isEmpty else {
            await MainActor.run {
                syncState.showError("Could not parse remote branch '\(fullPath)'.")
            }
            return
        }

        do {
            let localBranch = try await GitStatusService.shared.checkoutRemoteBranch(
                remote: remote,
                branch: branch,
                in: repositoryURL
            )
            await MainActor.run {
                selectedItem = .branch(localBranch)
            }
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

    private func presentCreateBranchSheet(startPoint: GitBranchStartPoint) {
        switch startPoint {
        case .commit:
            presentBranchSheet(startPoint: startPoint)
        case .branch(let sourceBranch):
            Task {
                await presentBranchSheetFromBranchTip(sourceBranch)
            }
        }
    }

    private func presentBranchSheetFromBranchTip(_ sourceBranch: String) async {
        let commits = await GitStatusService.shared.commitHistory(
            branch: sourceBranch,
            limit: 1,
            in: repositoryURL
        )

        await MainActor.run {
            if let commit = commits.first {
                presentBranchSheet(
                    startPoint: .commit(hash: commit.hash, message: commit.message)
                )
            } else {
                syncState.showError("Could not find the last commit for \(sourceBranch).")
            }
        }
    }

    private func presentBranchSheet(startPoint: GitBranchStartPoint?) {
        branchSheetStartPoint = startPoint
        showingBranchSheet = true
    }

    private func presentPushBranchDropConfirmation(_ branch: String) async {
        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        await MainActor.run {
            guard let remote = remotes.first(where: { $0 == "origin" }) ?? remotes.first else {
                syncState.showError("No remotes configured.")
                return
            }

            pendingPushBranchDropConfirmation = PendingPushBranchDropConfirmation(
                branch: branch,
                remote: remote
            )
        }
    }

    private func performConfirmedBranchPush(_ confirmation: PendingPushBranchDropConfirmation) async {
        let options = GitStatusService.PushOptions(
            remote: confirmation.remote,
            branches: [confirmation.branch],
            branchMappings: [confirmation.branch: confirmation.branch]
        )

        await syncState.performPush(
            options: options,
            repositoryURL: repositoryURL,
            undoManager: undoManager,
            credentialResolver: providerAccountController.credentialResolver()
        )
    }

    private func presentTagSheetFromBranchTip(_ sourceBranch: String) async {
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

    private func createTagFromBranch() async {
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

    private func resetTagSheet() {
        tagNameInput = ""
        branchTagStartPoint = nil
    }

    private func executeUndoEntry(_ entry: GitUndoEntry, menuAction: GitUndoMenuAction) async {
        let operation: GitUndoOperation
        switch menuAction {
        case .undo:
            operation = entry.undoOperation
        case .redo:
            operation = entry.redoOperation
        }

        do {
            try await undoExecutor.execute(operation, in: entry.repositoryURL)
            await syncState.refresh(repositoryURL: repositoryURL)
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
            await MainActor.run {
                switch menuAction {
                case .undo:
                    undoManager.completeUndo(entry)
                    syncState.showInfo("Undid \(entry.label).")
                case .redo:
                    undoManager.completeRedo(entry)
                    syncState.showInfo("Redid \(entry.label).")
                }
            }
        } catch {
            await MainActor.run {
                switch menuAction {
                case .undo:
                    undoManager.restoreUndo(entry)
                case .redo:
                    undoManager.restoreRedo(entry)
                }
                syncState.showError(error.localizedDescription)
            }
        }
    }

    private func handleSearchAction(_ action: SearchAction) {
        switch action {
        case .showCommit(let hash):
            selectedItem = .item(.history)
            selectedBranchName = hash
        case .showFile(let path):
            prepareToOpenSearchFile(path)
        case .checkoutBranch(let branch):
            if branch.hasPrefix("remotes/") {
                let localName = branch.replacingOccurrences(of: "remotes/", with: "")
                if let slashIndex = localName.firstIndex(of: "/") {
                    let branchName = String(localName[localName.index(after: slashIndex)...])
                    branchToCheckout = branchName
                    showingCheckoutConfirmation = true
                }
            } else {
                branchToCheckout = branch
                showingCheckoutConfirmation = true
            }
        case .showTag(let tag):
            tagToCheckout = tag
            showingDetachedHeadConfirmation = true
        }
    }

    private func prepareToOpenSearchFile(_ relativePath: String) {
        let applications = SearchFileApplicationResolver.availableApplications()

        if let preferredBundleIdentifier = appState.preferredSearchFileApplicationBundleIdentifier {
            if let preferredApplication = applications.first(where: {
                $0.bundleIdentifier == preferredBundleIdentifier
            }) {
                openSearchFile(relativePath, using: preferredApplication)
                return
            }

            appState.preferredSearchFileApplicationBundleIdentifier = nil
        }

        guard !applications.isEmpty else {
            syncState.showError("No supported application is available to open this file.")
            return
        }

        pendingSearchFileOpenRequest = SearchFileOpenRequest(
            relativePath: relativePath,
            applications: applications
        )
    }

    private func openSearchFile(
        _ relativePath: String,
        using application: SearchFileApplication
    ) {
        let progressID = operationProgress.begin(
            message: "Opening \((relativePath as NSString).lastPathComponent) in \(application.displayName)...",
            canCancel: false
        )

        Task {
            defer { operationProgress.end(progressID) }
            do {
                try await SearchFileOpener.open(
                    relativePath: relativePath,
                    in: repositoryURL,
                    using: application
                )
            } catch {
                syncState.showError(error.localizedDescription)
            }
        }
    }
}
