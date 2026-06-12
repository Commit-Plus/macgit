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
    @StateObject private var syncState = SyncState()
    @State private var repoIconName: String = "code-branch"
    @State private var remoteURLString: String = ""
    @State private var selectedBranchName: String? = nil
    @State private var pullPreselectedBranch: String? = nil

    var body: some View {
        NavigationSplitView {
            SidebarView(
                repositoryURL: repositoryURL,
                selection: $selectedItem,
                onRequestCheckout: { ref, isTag in
                    if isTag {
                        tagToCheckout = ref
                        showingDetachedHeadConfirmation = true
                    } else {
                        branchToCheckout = ref
                        showingCheckoutConfirmation = true
                    }
                },
                onRequestPullBranch: { branch in
                    pullPreselectedBranch = branch
                    showingPullSheet = true
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            VStack(spacing: 0) {
                Color(nsColor: .controlBackgroundColor)
                    .frame(height: 1)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.separator)
                            .frame(height: 0.5)
                    }

                Group {
                    switch selectedItem {
                    case .item(.fileStatus):
                        FileStatusView(repositoryURL: repositoryURL, syncState: syncState)
                    case .item(.history), .branch, .tag:
                        HistoryView(repositoryURL: repositoryURL, selectedBranch: selectedBranchName)
                    case .item(.search):
                        SearchView(repositoryURL: repositoryURL)
                    case .none:
                        EmptyStateView(message: "Select an item from the sidebar")
                    }
                }
            }
        }
        .overlay(
            GeometryReader { geo in
                Color.clear.preference(key: WindowWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(WindowWidthKey.self) { newWidth in
            windowWidth = newWidth
        }
        .toolbar {
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
                toolbarButton(icon: "network", label: "Remote", disabled: remoteURLString.isEmpty, action: openRemoteURL)
            }
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "folder", label: "Finder", action: showInFinder)
            }
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "terminal", label: "Terminal", action: openTerminal)
            }
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "gear", label: "Settings", action: {})
            }
        }
        .navigationTitle("")
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await syncState.refresh(repositoryURL: repositoryURL)
            syncState.startBackgroundSync(repositoryURL: repositoryURL)
            let remoteURLString = await GitStatusService.shared.remoteURL(remote: "origin", in: repositoryURL)
            if !remoteURLString.isEmpty {
                self.remoteURLString = remoteURLString
                repoIconName = determineRepoIconName(from: remoteURLString)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            if case .branch(let name) = newItem {
                selectedBranchName = name
            } else if case .tag(let name) = newItem {
                selectedBranchName = name
            } else {
                selectedBranchName = nil
            }
        }
        .onDisappear {
            syncState.stopBackgroundSync()
        }
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
        .sheet(isPresented: $showingCommitSheet) {
            CommitSheetView { message in
                Task {
                    await commitFromToolbar(message: message)
                }
            }
        }
        .sheet(isPresented: $showingPullSheet) {
            PullSheetView(repositoryURL: repositoryURL, preselectedBranch: pullPreselectedBranch) { remote, branch, options in
                Task {
                    await syncState.performPull(remote: remote, branch: branch, options: options, repositoryURL: repositoryURL)
                }
            }
        }
        .sheet(isPresented: $showingPushSheet) {
            PushSheetView(repositoryURL: repositoryURL) { options in
                Task {
                    await syncState.performPush(options: options, repositoryURL: repositoryURL)
                }
            }
        }
        .sheet(isPresented: $showingFetchSheet) {
            FetchSheetView(repositoryURL: repositoryURL) { options in
                Task {
                    await syncState.performFetch(options: options, repositoryURL: repositoryURL)
                }
            }
        }
        .sheet(isPresented: $showingBranchSheet) {
            BranchSheetView(repositoryURL: repositoryURL) {
                Task {
                    await syncState.refresh(repositoryURL: repositoryURL)
                }
            }
        }
        .sheet(isPresented: $showingMergeSheet) {
            MergeSheetView(repositoryURL: repositoryURL) { branch, message, options in
                Task {
                    await syncState.performMerge(branch: branch, options: options, repositoryURL: repositoryURL)
                }
            }
        }
        .sheet(isPresented: $showingStashSheet) {
            StashSheetView { options in
                Task {
                    await syncState.performStash(options: options, repositoryURL: repositoryURL)
                }
            }
        }
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
            Task {
                await syncState.refresh(repositoryURL: repositoryURL)
            }
        }
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
            ToolbarButtonLabel(icon: "ellipsis", label: "")
        }
        .help("More Actions")
    }

    private func showCommitSheetIfNoConflicts() {
        Task {
            if await syncState.checkConflicts(repositoryURL: repositoryURL) { return }
            showingCommitSheet = true
        }
    }

    private func commitFromToolbar(message: String) async {
        await syncState.performCommit(message: message, repositoryURL: repositoryURL)
    }

    private func performCheckout(ref: String, stash: Bool) async {
        do {
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

    private func openRemoteURL() {
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
}
