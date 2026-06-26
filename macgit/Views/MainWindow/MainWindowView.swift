//
//  MainWindowView.swift
//  macgit
//

import SwiftUI

struct WindowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MainWindowView: View {
    let repositoryURL: URL
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
    @State private var showingMergeSheet = false
    @State private var showingStashSheet = false
    @State private var showingCheckoutConfirmation = false
    @State private var branchToCheckout: String = ""
    @State private var showingDetachedHeadConfirmation = false
    @State private var tagToCheckout: String = ""
    @State private var pendingStashRef: String?
    @State private var pendingStashAction: StashAction?
    @StateObject private var syncState = SyncState()
    @StateObject private var undoManager = GitUndoManager()
    @State private var repoIconName: String = "code-branch"
    @State private var remoteURLString: String = ""
    @State private var selectedBranchName: String? = nil
    @State private var pullPreselectedBranch: String? = nil
    @State private var showingSearchModal = false
    @State private var showingRepositorySettings = false
    @State private var repoSettings = RepoSettings.defaults(currentBranch: nil, remotes: [])
    @State private var pendingConfirmedUndo: (entry: GitUndoEntry, action: GitUndoMenuAction)?

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
                    Task {
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
            .sheet(isPresented: $showingBranchSheet) { branchSheet }
            .sheet(isPresented: $showingMergeSheet) { mergeSheet }
            .sheet(isPresented: $showingStashSheet) { stashSheet }
            .sheet(isPresented: $showingRepositorySettings) { repositorySettingsSheet }
            .sheet(isPresented: stashActionSheetBinding) { stashActionSheet }
            .sheet(isPresented: $showingCheckoutConfirmation) {
                CheckoutConfirmationSheet(branchName: branchToCheckout) { stash in
                    Task {
                        await performCheckout(ref: branchToCheckout, stash: stash)
                    }
                }
            }
            .alert("Confirm change working copy", isPresented: $showingDetachedHeadConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("OK") {
                    Task {
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
                        onDismiss: { showingSearchModal = false },
                        onSelect: { action in
                            handleSearchAction(action)
                            showingSearchModal = false
                        }
                    )
                    .padding(.top, 80)
                }
                .transition(.opacity)
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
                Task {
                    await syncState.performPullBranch(
                        branch: branch,
                        repositoryURL: repositoryURL,
                        undoManager: undoManager
                    )
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
            }
        )
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
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
                    undoManager: undoManager
                )
            case .item(.history), .branch, .worktree, .tag, .remoteBranch, .head:
                HistoryView(
                    repositoryURL: repositoryURL,
                    selectedBranch: selectedBranchName,
                    undoManager: undoManager,
                    syncState: syncState
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
                disabled: GitUndoToolbarPolicy.isUndoDisabled(
                    isSyncing: syncState.isAnySyncing,
                    canUndo: undoManager.canUndo
                ),
                action: { handleGitUndoMenuAction(.undo) }
            )
        }
        ToolbarItem(placement: .automatic) {
            toolbarButton(icon: "network", label: "Remote", disabled: remoteURLString.isEmpty, action: { openRemoteURL() })
        }
        ToolbarItem(placement: .automatic) {
            toolbarButton(icon: "folder", label: "Finder", action: showInFinder)
        }
        ToolbarItem(placement: .automatic) {
            toolbarButton(icon: "terminal", label: "Terminal", action: openTerminal)
        }
        ToolbarItem(placement: .automatic) {
            toolbarButton(icon: "gear", label: "Settings", action: { showingRepositorySettings = true })
        }
    }

    @ViewBuilder
    private var commitSheet: some View {
        CommitSheetView { message in
            Task {
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
            Task {
                await syncState.performPull(
                    remote: remote,
                    branch: branch,
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager
                )
            }
        }
    }

    @ViewBuilder
    private var pushSheet: some View {
        PushSheetView(repositoryURL: repositoryURL) { options in
            Task {
                await syncState.performPush(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager
                )
            }
        }
    }

    @ViewBuilder
    private var fetchSheet: some View {
        FetchSheetView(repositoryURL: repositoryURL) { options in
            Task {
                await syncState.performFetch(options: options, repositoryURL: repositoryURL)
            }
        }
    }

    @ViewBuilder
    private var branchSheet: some View {
        BranchSheetView(repositoryURL: repositoryURL, undoManager: undoManager) {
            Task {
                await syncState.refresh(repositoryURL: repositoryURL)
            }
        }
    }

    @ViewBuilder
    private var mergeSheet: some View {
        MergeSheetView(repositoryURL: repositoryURL) { branch, message, options in
            Task {
                await syncState.performMerge(branch: branch, options: options, repositoryURL: repositoryURL)
            }
        }
    }

    @ViewBuilder
    private var stashSheet: some View {
        StashSheetView { options in
            Task {
                await syncState.performStash(
                    options: options,
                    repositoryURL: repositoryURL,
                    undoManager: undoManager
                )
            }
        }
    }

    @ViewBuilder
    private var stashActionSheet: some View {
        if let ref = pendingStashRef, let action = pendingStashAction {
            StashActionConfirmationSheet(stashRef: ref, action: action) { deleteAfterApplying in
                Task {
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
    }

    @ViewBuilder
    private var leftToolbar: some View {
        let syncing = syncState.isAnySyncing
        if windowWidth > 1000 {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing || syncState.stagedBadgeCount == 0, action: { showCommitSheetIfNoConflicts() })
                BadgeToolbarButton(icon: "arrow.down.to.line", label: "Pull", badgeCount: syncState.pullBadgeCount, isLoading: syncState.isPulling, disabled: syncing, action: { showingPullSheet = true })
                BadgeToolbarButton(icon: "arrow.up.to.line", label: "Push", badgeCount: syncState.pushBadgeCount, isLoading: syncState.isPushing, disabled: syncing, action: { showingPushSheet = true })
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", isLoading: syncState.isFetching, disabled: syncing, action: { showingFetchSheet = true })
                toolbarButton(icon: "arrow.triangle.branch", label: "Branch", action: { showingBranchSheet = true })
                toolbarButton(icon: "arrow.triangle.merge", label: "Merge", isLoading: syncState.isMerging, disabled: syncing, action: { showingMergeSheet = true })
                toolbarButton(icon: "archivebox", label: "Stash", isLoading: syncState.isStashing, disabled: syncing || syncState.stashableCount == 0, action: { showingStashSheet = true })
            }
        } else if windowWidth > 800 {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing || syncState.stagedBadgeCount == 0, action: { showCommitSheetIfNoConflicts() })
                BadgeToolbarButton(icon: "arrow.down.to.line", label: "Pull", badgeCount: syncState.pullBadgeCount, isLoading: syncState.isPulling, disabled: syncing, action: { showingPullSheet = true })
                BadgeToolbarButton(icon: "arrow.up.to.line", label: "Push", badgeCount: syncState.pushBadgeCount, isLoading: syncState.isPushing, disabled: syncing, action: { showingPushSheet = true })
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", isLoading: syncState.isFetching, disabled: syncing, action: { showingFetchSheet = true })
                moreMenu
            }
        } else {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing || syncState.stagedBadgeCount == 0, action: { showCommitSheetIfNoConflicts() })
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
                Button("Branch") { showingBranchSheet = true }
                Button("Merge") { showingMergeSheet = true }
                    .disabled(syncing)
                Button("Stash", action: { showingStashSheet = true })
                    .disabled(syncing || syncState.stashableCount == 0)
            }
        } label: {
            ToolbarButtonLabel(icon: "ellipsis", label: "More")
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
            showingBranchSheet = true
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
        case .showFile(_):
            selectedItem = .item(.fileStatus)
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
}
