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
    @State private var selectedItem: SidebarItem? = .fileStatus
    @State private var windowWidth: CGFloat = 0
    @State private var showingCommitSheet = false
    @State private var showingPullSheet = false
    @State private var showingPushSheet = false
    @StateObject private var syncState = SyncState()

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            Group {
                switch selectedItem {
                case .fileStatus:
                    FileStatusView(repositoryURL: repositoryURL, syncState: syncState)
                case .history:
                    HistoryView(repositoryURL: repositoryURL)
                case .search:
                    SearchView(repositoryURL: repositoryURL)
                case .none:
                    EmptyStateView(message: "Select an item from the sidebar")
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
                    Image("code-branch")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                    Text(repositoryURL.lastPathComponent)
                        .font(.headline)
                }
                .padding(.horizontal, 12)
            }

            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "network", label: "Remote", action: {})
            }
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "folder", label: "Finder", action: {})
            }
            ToolbarItem(placement: .automatic) {
                toolbarButton(icon: "terminal", label: "Terminal", action: {})
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
            PullSheetView(repositoryURL: repositoryURL) { remote, branch, options in
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
    }

    @ViewBuilder
    private var leftToolbar: some View {
        let syncing = syncState.isAnySyncing
        if windowWidth > 1000 {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing, action: { showCommitSheetIfNoConflicts() })
                BadgeToolbarButton(icon: "arrow.down.to.line", label: "Pull", badgeCount: syncState.pullBadgeCount, isLoading: syncState.isPulling, disabled: syncing, action: { showingPullSheet = true })
                BadgeToolbarButton(icon: "arrow.up.to.line", label: "Push", badgeCount: syncState.pushBadgeCount, isLoading: syncState.isPushing, disabled: syncing, action: { showingPushSheet = true })
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", isLoading: syncState.isFetching, disabled: syncing, action: { performFetch() })
                toolbarButton(icon: "arrow.triangle.branch", label: "Branch", action: {})
                toolbarButton(icon: "arrow.triangle.merge", label: "Merge", action: {})
                toolbarButton(icon: "archivebox", label: "Stash", action: {})
            }
        } else if windowWidth > 800 {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing, action: { showCommitSheetIfNoConflicts() })
                BadgeToolbarButton(icon: "arrow.down.to.line", label: "Pull", badgeCount: syncState.pullBadgeCount, isLoading: syncState.isPulling, disabled: syncing, action: { showingPullSheet = true })
                BadgeToolbarButton(icon: "arrow.up.to.line", label: "Push", badgeCount: syncState.pushBadgeCount, isLoading: syncState.isPushing, disabled: syncing, action: { showingPushSheet = true })
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", isLoading: syncState.isFetching, disabled: syncing, action: { performFetch() })
                moreMenu
            }
        } else {
            HStack(spacing: 2) {
                BadgeToolbarButton(icon: "checkmark", label: "Commit", badgeCount: syncState.commitBadgeCount, isLoading: syncState.isCommitting, disabled: syncing, action: { showCommitSheetIfNoConflicts() })
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
                Button("Fetch") { performFetch() }
                    .disabled(syncing)
            }
            if windowWidth <= 1000 {
                Button("Branch", action: {})
                Button("Merge", action: {})
                Button("Stash", action: {})
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

    private func performFetch() {
        Task {
            await syncState.performFetch(repositoryURL: repositoryURL)
        }
    }

    private func commitFromToolbar(message: String) async {
        await syncState.performCommit(message: message, repositoryURL: repositoryURL)
    }
}
