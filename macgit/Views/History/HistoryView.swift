//
//  HistoryView.swift
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
import CoreTransferable
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class HistorySelectionStore: ObservableObject {
    @Published var selectedCommits: [Commit] = []
}

struct HistoryView: View {
    private struct SquashSheetPresentation: Identifiable {
        let id = UUID()
        let commits: [Commit]
        let message: String
    }

    let repositoryURL: URL
    let selectedBranch: String?
    let undoManager: GitUndoManager?
    var syncState: SyncState? = nil
    let onRunRepositoryOperation: RepositoryOperationRunner
    let onRequestCheckout: (String, Bool) -> Void
    let onRequestExplainCommit: (Commit) -> Void
    @EnvironmentObject private var appState: AppState
    private static let historyScrollSpaceName = "historyScroll"
    
    @State private var commits: [Commit] = []
    @State private var graphModel: CommitGraphModel? = nil
    @State private var commitSelection = HistoryCommitSelection()
    @StateObject private var historySelectionStore = HistorySelectionStore()
    @State private var activeDragCommitHashes: Set<String> = []
    @State private var activeCommitDragPayload: GitDragPayload?
    @State private var suppressedCommitClickHash: String?
    @State private var dragClickSuppressionTask: Task<Void, Never>?
    @State private var dragCompletionMonitorTask: Task<Void, Never>?
    @State private var selectedCommit: Commit? = nil
    @State private var fileChanges: [CommitFileChange] = []
    @State private var selectedFile: CommitFileChange? = nil
    @State private var diffHunks: [DiffHunk] = []
    @State private var commitFilesLoadID = UUID()
    @State private var diffLoadID = UUID()
    @AppStorage("history.messageWidth") private var messageColumnWidth: Double = 200
    @AppStorage("history.authorWidth") private var authorColumnWidth: Double = 120
    @AppStorage("history.dateWidth") private var dateColumnWidth: Double = 80
    @AppStorage("history.commitWidth") private var commitColumnWidth: Double = 70
    @AppStorage("advanced.historyLoadSize") private var historyLoadSizeRaw = 120
    @State private var isLoading = false
    @State private var isRefreshingHistory = false
    @State private var refreshIndicatorTask: Task<Void, Never>? = nil
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var scrollTarget: String? = nil
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var paging = HistoryPagingState(pageSize: 120)
    @State private var historyCache: [String: HistorySnapshot] = [:]
    @State private var historySearchText = ""
    @State private var debouncedHistorySearchText = ""
    @State private var historySearchDebounceTask: Task<Void, Never>? = nil
    
    // MARK: - Context menu confirmation / sheet state
    @State private var showingResetConfirmation = false
    @State private var showingRevertConfirmation = false
    @State private var showingTagSheet = false
    @State private var showingBranchSheet = false
    @State private var tagNameInput = ""
    @State private var branchNameInput = ""
    @State private var checkoutNewBranch = true
    @State private var pendingCommit: Commit? = nil
    
    // MARK: - Checkout confirmation state
    @State private var showingCheckoutConfirmation = false
    @State private var discardLocalChanges = false
    @State private var hasUncommittedChanges = false
    @State private var resetMode: ResetMode = .mixed
    @State private var currentBranchName: String = ""
    
    // MARK: - Merge / Rebase confirmation state
    @State private var showingMergeConfirmation = false
    @State private var showingRebaseConfirmation = false
    @State private var mergeCommitImmediately = true
    @State private var mergeIncludeMessages = true
    @State private var squashSheetPresentation: SquashSheetPresentation?
    @State private var currentHeadHash: String?
    
    init(
        repositoryURL: URL,
        selectedBranch: String? = nil,
        undoManager: GitUndoManager? = nil,
        syncState: SyncState? = nil,
        onRunRepositoryOperation: @escaping RepositoryOperationRunner = { _, operation in
            Task { await operation() }
        },
        onRequestCheckout: @escaping (String, Bool) -> Void = { _, _ in },
        onRequestExplainCommit: @escaping (Commit) -> Void = { _ in }
    ) {
        self.repositoryURL = repositoryURL
        self.selectedBranch = selectedBranch
        self.undoManager = undoManager
        self.syncState = syncState
        self.onRunRepositoryOperation = onRunRepositoryOperation
        self.onRequestCheckout = onRequestCheckout
        self.onRequestExplainCommit = onRequestExplainCommit
        let storedPageSize = UserDefaults.standard.integer(forKey: "advanced.historyLoadSize")
        self._paging = State(
            initialValue: HistoryPagingState(
                pageSize: HistoryLoadSize(rawValue: storedPageSize)?.rawValue
                    ?? HistoryLoadSize.balanced.rawValue
            )
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            BranchFilterBar(
                repositoryURL: repositoryURL,
                selectedFilter: $appState.historyBranchFilter,
                includeRemotes: $appState.historyIncludeRemotes,
                searchText: $historySearchText
            )
            
            if isLoading && commits.isEmpty {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commits.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    message: activeHistorySearchQuery.isEmpty ? "No commits to display" : "No matching commits",
                    detail: activeHistorySearchQuery.isEmpty ? "Repository may be empty" : "Try author name, email, or commit ID"
                )
            } else {
                ZStack(alignment: .top) {
                    PersistentVSplit(
                        autosaveName: "HistoryMainSplit",
                        top: { commitGraphList.frame(minHeight: 200) },
                        bottom: { commitDetailPanel.frame(minHeight: 180) }
                    )

                    if isRefreshingHistory {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading branch history…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, 8)
                    }
                }
            }
        }
        .id("history")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: selectedCommit) { _, newCommit in
            Task {
                await loadFileChanges(for: newCommit)
            }
        }
        .onChange(of: selectedFile) { _, newFile in
            Task {
                await loadDiff(for: newFile, in: selectedCommit)
            }
        }
        .onChange(of: selectedBranch) { _, newBranch in
            if appState.historyBranchFilter != .all {
                appState.historyBranchFilter = newBranch.map(HistoryBranchFilter.branch) ?? .current
            }
        }
        .onChange(of: historySearchText) { _, newValue in
            scheduleHistorySearchDebounce(for: newValue)
        }
        .onChange(of: historyLoadSizeRaw) { _, newValue in
            let pageSize = HistoryLoadSize(rawValue: newValue)?.rawValue
                ?? HistoryLoadSize.balanced.rawValue
            paging = HistoryPagingState(pageSize: pageSize)
            historyCache.removeAll()
        }
        .onDisappear {
            historySearchDebounceTask?.cancel()
            dragClickSuppressionTask?.cancel()
            dragCompletionMonitorTask?.cancel()
            activeDragCommitHashes.removeAll()
        }
        .task(id: historyLoadKey) {
            await loadHistory(reset: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL,
               url == repositoryURL {
                historyCache.removeAll()
                Task {
                    await loadHistory(reset: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .advancedClearSessionCaches)) { _ in
            historyCache.removeAll()
            Task {
                await loadHistory(reset: true)
            }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .sheet(isPresented: $showingResetConfirmation) {
            resetSheet
        }
        .alert("Reverse this commit?", isPresented: $showingRevertConfirmation, actions: {
            Button("Cancel", role: .cancel) {}
            Button("Revert") {
                Task {
                    await performRevert()
                }
            }
        }, message: {
            Text("This will create a new commit that undoes the changes in \(pendingCommit?.shortHash ?? "").")
        })
        .sheet(isPresented: $showingTagSheet) {
            tagSheet
        }
        .sheet(isPresented: $showingBranchSheet) {
            branchSheet
        }
        .sheet(isPresented: $showingMergeConfirmation) {
            mergeConfirmationSheet
        }
        .sheet(isPresented: $showingRebaseConfirmation) {
            rebaseConfirmationSheet
        }
        .sheet(item: $squashSheetPresentation) { presentation in
            SquashCommitsSheet(
                commits: presentation.commits,
                initialMessage: presentation.message,
                onCancel: {
                    squashSheetPresentation = nil
                },
                onConfirm: { message in
                    let commits = presentation.commits
                    onRunRepositoryOperation("Squashing \(commits.count) commits...") {
                        await performSquash(commits: commits, message: message)
                    }
                }
            )
        }
        .sheet(isPresented: $showingCheckoutConfirmation) {
            checkoutConfirmationSheet
        }
    }
    
    // MARK: - Sheets
    
    private var tagSheet: some View {
        VStack(spacing: 16) {
            Text("Create Tag")
                .font(.title2)
                .fontWeight(.semibold)
            
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
                    onRunRepositoryOperation("Creating tag \(tagNameInput)...") {
                        await performCreateTag()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tagNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320, idealWidth: 360)
    }
    
    private var branchSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Branch")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("From commit:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(pendingCommit?.shortHash ?? "") : \(pendingCommit?.message ?? "")")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Branch name:")
                    .font(.system(size: 13))
                TextField("Enter branch name...", text: $branchNameInput)
                    .textFieldStyle(.roundedBorder)
            }
            
            Toggle("Checkout new branch", isOn: $checkoutNewBranch)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingBranchSheet = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create Branch") {
                    onRunRepositoryOperation("Creating branch \(branchNameInput)...") {
                        await performCreateBranch()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
    
    private var resetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reset to this commit?")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("This will reset '")
                        .font(.system(size: 13))
                    Text(currentBranchName.isEmpty ? "current branch" : currentBranchName)
                        .font(.system(size: 13, weight: .bold))
                    Text("' to:")
                        .font(.system(size: 13))
                }
                Text("\(pendingCommit?.shortHash ?? "") : \(pendingCommit?.message ?? "")")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Reset mode:")
                    .font(.system(size: 13))
                
                Picker("", selection: $resetMode) {
                    Text("Soft – keep all local changes").tag(ResetMode.soft)
                    Text("Mixed – keep working copy but reset index").tag(ResetMode.mixed)
                    Text("Hard – discard all working copy changes").tag(ResetMode.hard)
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 12))
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingResetConfirmation = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Reset", role: .destructive) {
                    onRunRepositoryOperation("Resetting HEAD...") {
                        await performReset()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
    
    private var mergeConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Merge")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Are you sure you want to merge into your current branch?")
                .font(.system(size: 13))
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Commit merged changes immediately", isOn: $mergeCommitImmediately)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                Toggle("Include messages from commits being merged in merge commit", isOn: $mergeIncludeMessages)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingMergeConfirmation = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("OK") {
                    onRunRepositoryOperation("Merging commit...") {
                        await performMerge()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 460)
    }
    
    private var rebaseConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm Rebase")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Are you sure you want to rebase your current changes on to '\(pendingCommit?.shortHash ?? "")'?")
                .font(.system(size: 13))
            
            Text("Make sure your changes have not been pushed to anyone else.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingRebaseConfirmation = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("OK") {
                    onRunRepositoryOperation("Rebasing onto commit...") {
                        await performRebase()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }

    private var checkoutConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Confirm change working copy")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Are you sure you want to checkout '\(pendingCommit?.shortHash ?? "")'?")
                .font(.system(size: 13))
            
            Text("Doing so will make your working copy a 'detached HEAD', which means you won't be on a branch anymore. If you want to commit after this you'll probably want to either checkout a branch again, or create a new branch. Is this ok?")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            if hasUncommittedChanges {
                Toggle("Discard local changes", isOn: $discardLocalChanges)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showingCheckoutConfirmation = false
                    hasUncommittedChanges = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("OK") {
                    onRunRepositoryOperation("Checking out commit...") {
                        await performCheckoutCommit()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420)
    }
    
    // MARK: - Top Panel
    
    private var graphWidth: CGFloat {
        let maxLane = graphModel?.laneCount ?? 1
        return CGFloat(maxLane) * 14 + 4
    }

    private func commitListHeader(messageWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: graphWidth, height: 16)
                .fixedSize()

            Text("Message")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: messageWidth, alignment: .leading)

            ColumnResizer(
                leftWidth: Binding(
                    // Include viewport fill space so the divider can resize the
                    // full visible Message column, not only its persisted base.
                    get: { messageWidth },
                    set: { messageColumnWidth = Double($0) }
                ),
                rightWidth: Binding(
                    get: { CGFloat(authorColumnWidth) },
                    set: { authorColumnWidth = Double($0) }
                ),
                minimumLeftWidth: 27
            )

            Text("Author")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: CGFloat(authorColumnWidth), alignment: .leading)

            ColumnResizer(
                leftWidth: Binding(
                    get: { CGFloat(authorColumnWidth) },
                    set: { authorColumnWidth = Double($0) }
                ),
                rightWidth: Binding(
                    get: { CGFloat(dateColumnWidth) },
                    set: { dateColumnWidth = Double($0) }
                )
            )

            Text("Date")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: CGFloat(dateColumnWidth), alignment: .trailing)

            ColumnResizer(
                leftWidth: Binding(
                    get: { CGFloat(dateColumnWidth) },
                    set: { dateColumnWidth = Double($0) }
                ),
                rightWidth: Binding(
                    get: { CGFloat(commitColumnWidth) },
                    set: { commitColumnWidth = Double($0) }
                )
            )

            Text("Commit")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: CGFloat(commitColumnWidth), alignment: .trailing)

            ColumnResizer(
                leftWidth: Binding(
                    get: { CGFloat(commitColumnWidth) },
                    set: { commitColumnWidth = Double($0) }
                ),
                rightWidth: Binding(
                    get: { CGFloat(0) },
                    set: { _ in }
                )
            )
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(height: 20)
        .background(.thinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var commitGraphList: some View {
        GeometryReader { geometry in
            let viewportWidth = geometry.size.width
            let resizers: CGFloat = 4 * 6
            let padding: CGFloat = 8 + 16
            let fixedWidth = graphWidth + CGFloat(messageColumnWidth) + CGFloat(authorColumnWidth) + CGFloat(dateColumnWidth) + CGFloat(commitColumnWidth) + resizers + padding
            let extraSpace = max(0, viewportWidth - fixedWidth)
            let effectiveMessageWidth = CGFloat(messageColumnWidth) + extraSpace

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    commitListHeader(messageWidth: effectiveMessageWidth)

                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            ZStack(alignment: .topLeading) {
                                // Graph lines
                                if let model = graphModel {
                                    BranchGraphCanvas(model: model)
                                    .padding(.leading, 4)
                                }

                                // Commit rows overlay
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    if graphModel != nil {
                                        ForEach(commits) { commit in
                                            let draggedCommits = Self.draggedCommits(
                                                startingAt: commit.hash,
                                                commits: commits,
                                                selection: commitSelection
                                            )
                                            let draggedHashes = Set(draggedCommits.map(\.hash))
                                            let draggedPayload = GitDragPayload.commits(
                                                draggedCommits,
                                                repositoryURL: repositoryURL
                                            )

                                            CommitRowView(
                                                commit: commit,
                                                graphWidth: graphWidth,
                                                isSelected: commitSelection.selectedHashes.contains(commit.hash),
                                                isDragActive: activeDragCommitHashes.contains(commit.hash),
                                                graphColorIndex: graphModel?.commitMetadata[commit.hash]?.colorIndex,
                                                messageWidth: effectiveMessageWidth,
                                                authorWidth: CGFloat(authorColumnWidth),
                                                dateWidth: CGFloat(dateColumnWidth),
                                                commitWidth: CGFloat(commitColumnWidth),
                                                onClick: {
                                                    guard !consumeSuppressedCommitClick(commit.hash) else { return }
                                                    selectedCommit = Self.selectCommitFromNativeTap(
                                                        commit.hash,
                                                        modifierFlags: NSEvent.modifierFlags,
                                                        commits: commits,
                                                        selection: &commitSelection
                                                    )
                                                    syncSelectedCommitSnapshot()
                                                },
                                                onDoubleClick: {
                                                    handleCommitDoubleClick(commit)
                                                }
                                            )
                                            .id(commit.hash)
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: CommitRowFramePreferenceKey.self,
                                                        value: [commit.hash: geo.frame(in: .named(Self.historyScrollSpaceName))]
                                                    )
                                                }
                                            )
                                            .onClick(left: { _ in }, right: {
                                                selectCommitForContextMenu(commit)
                                            })
                                            .contextMenu {
                                                commitContextMenu(for: commit)
                                            }
                                            .onDrag {
                                                let liveDraggedCommits = Self.draggedCommits(
                                                    startingAt: commit.hash,
                                                    commits: commits,
                                                    selection: commitSelection
                                                )
                                                let livePayload = GitDragPayload.commits(
                                                    liveDraggedCommits,
                                                    repositoryURL: repositoryURL
                                                )
                                                beginCommitDrag(
                                                    startingAt: commit.hash,
                                                    payload: livePayload
                                                )
                                                if !commitSelection.selectedHashes.contains(commit.hash) {
                                                    selectedCommit = Self.selectCommitFromNativeTap(
                                                        commit.hash,
                                                        modifierFlags: [],
                                                        commits: commits,
                                                        selection: &commitSelection
                                                    )
                                                    syncSelectedCommitSnapshot()
                                                }
                                                return makeCommitItemProvider(payload: livePayload)
                                            } preview: {
                                                CommitDragPreview(
                                                    presentation: CommitDragPreviewPresentation(
                                                        commit: commit,
                                                        commitCount: activeCommitDragPayload?.commits.count
                                                            ?? draggedCommits.count
                                                    ),
                                                    onDragStateChange: { isActive in
                                                        updateCommitDragState(
                                                            isActive: isActive,
                                                            hashes: draggedHashes,
                                                            payload: draggedPayload
                                                        )
                                                    }
                                                )
                                            }
                                            .onAppear {
                                                if commit.hash == commits.last?.hash {
                                                    Task {
                                                        await loadOlderHistoryIfNeeded()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    if paging.isLoadingMore {
                                        HStack {
                                            Spacer()
                                            ProgressView("Loading older commits…")
                                                .font(.caption)
                                                .padding(.vertical, 12)
                                            Spacer()
                                        }
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                        .coordinateSpace(name: Self.historyScrollSpaceName)
                        .onPreferenceChange(CommitRowFramePreferenceKey.self) { frames in
                            rowFrames = frames
                        }
                        .task(id: scrollTarget) {
                            guard let target = scrollTarget else { return }
                            let viewportHeight = max(0, geometry.size.height - 20)
                            var attempts = 0
                            while rowFrames[target] == nil, attempts < 5 {
                                attempts += 1
                                await Task.yield()
                            }
                            if Self.shouldAutoCenterCommit(
                                targetHash: target,
                                rowFrames: rowFrames,
                                viewportHeight: viewportHeight
                            ) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(target, anchor: .center)
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: viewportWidth)
            }
        }
        .id(historyLoadKey)
    }
    
    // MARK: - Bottom Panel
    
    private var commitDetailPanel: some View {
        Group {
            if let commit = selectedCommit {
                VStack(spacing: 0) {
                    // Commit info header
                    commitInfoHeader(for: commit)
                    
                    PersistentHSplit(
                        autosaveName: "HistoryDetailSplit",
                        left: {
                            CommitFileListView(changes: fileChanges, selectedFile: $selectedFile)
                                .frame(minWidth: 220)
                        },
                        right: {
                            commitDiffViewer
                                .frame(minWidth: 300)
                        }
                    )
                }
            } else {
                EmptyStateView(
                    icon: "doc.text",
                    message: "Select a commit",
                    detail: "Click a commit above to see its changes"
                )
            }
        }
    }
    
    private func commitInfoHeader(for commit: Commit) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(commit.message)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(commit.author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(commit.hash)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            if !commit.refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(commit.refs.prefix(5), id: \.self) { ref in
                        RefLabel(text: ref)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }
    
    private var commitDiffViewer: some View {
        Group {
            if let file = selectedFile {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.primary)
                            .font(.system(size: 14, weight: .medium))
                        Text(file.path)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.separator)
                            .frame(height: 0.5)
                    }
                    
                    DiffView(
                        hunks: diffHunks,
                        file: nil,
                        repositoryURL: repositoryURL,
                        undoManager: nil,
                        onRefresh: {},
                        onError: { _ in },
                        filePath: file.path,
                        gitRef: selectedCommit.map(\.hash)
                    )
                }
            } else {
                EmptyStateView(
                    icon: "doc.text",
                    message: "Select a file",
                    detail: "Click a file on the left to see its diff"
                )
            }
        }
    }
    
    // MARK: - Context Menu
    
    private func commitContextMenu(for commit: Commit) -> some View {
        let contextCommits = Self.contextMenuCommits(
            startingAt: commit.hash,
            commits: commits,
            selection: commitSelection
        )
        let singleCommit = contextCommits.count == 1 ? contextCommits[0] : nil
        let cherryPickCommits = Self.cherryPickCommits(from: contextCommits)
        let canCherryPick = !cherryPickCommits.isEmpty
            && cherryPickCommits.allSatisfy { !$0.isMerge }
        let squashCommits = commitSelection.selectedHashes.contains(commit.hash)
            ? squashableCommits
            : contextCommits
        let canSquashCommits = Self.canSquashCommits(
            squashCommits,
            selectedHashes: squashCommits.map(\.hash),
            headHash: currentHeadHash
        )

        return Group {
            Button("Checkout Commit", systemImage: "arrow.right.to.line") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                discardLocalChanges = false
                showingCheckoutConfirmation = true
            }
            .disabled(singleCommit == nil)

            Button(
                contextCommits.count > 1 ? "Cherry Pick \(contextCommits.count) Commits" : "Cherry Pick",
                systemImage: "arrow.down.doc"
            ) {
                onRunRepositoryOperation(
                    cherryPickCommits.count == 1
                        ? "Cherry-picking \(cherryPickCommits[0].hash.prefix(7))..."
                        : "Cherry-picking \(cherryPickCommits.count) commits..."
                ) {
                    await performCherryPick(cherryPickCommits)
                }
            }
            .disabled(!canCherryPick)

            Button("AI Explain This Commit", systemImage: "sparkles") {
                onRequestExplainCommit(commit)
            }
            
            Divider()
            
            Button("Merge...", systemImage: "arrow.triangle.merge") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                mergeCommitImmediately = true
                mergeIncludeMessages = true
                showingMergeConfirmation = true
            }
            .disabled(singleCommit == nil)

            Button("Rebase...", systemImage: "arrow.triangle.swap") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                showingRebaseConfirmation = true
            }
            .disabled(singleCommit == nil)

            Divider()

            Button("Squash Commits", systemImage: "rectangle.compress.vertical") {
                squashSheetPresentation = SquashSheetPresentation(
                    commits: squashCommits,
                    message: squashCommits.map(\.message).joined(separator: "\n")
                )
            }
            .disabled(!canSquashCommits)
            
            Divider()
            
            Button("Tag...", systemImage: "tag") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                tagNameInput = ""
                showingTagSheet = true
            }
            .disabled(singleCommit == nil)

            Button("Branch...", systemImage: "arrow.triangle.branch") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                branchNameInput = ""
                checkoutNewBranch = true
                showingBranchSheet = true
            }
            .disabled(singleCommit == nil)
            
            Divider()
            
            Button("Reset to this commit", systemImage: "arrow.counterclockwise") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                resetMode = .mixed
                Task {
                    let branch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
                    await MainActor.run {
                        currentBranchName = branch
                        showingResetConfirmation = true
                    }
                }
            }
            .disabled(singleCommit == nil)

            Button("Reverse commit...", systemImage: "arrow.uturn.backward") {
                guard let singleCommit else { return }
                pendingCommit = singleCommit
                showingRevertConfirmation = true
            }
            .disabled(singleCommit == nil)
            
            Divider()
            
            Button(
                contextCommits.count > 1 ? "Copy Hashes" : "Copy Hash",
                systemImage: "doc.on.doc"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    contextCommits.map(\.hash).joined(separator: "\n"),
                    forType: .string
                )
            }
            .disabled(contextCommits.isEmpty)

            Button(
                contextCommits.count > 1 ? "Copy Messages" : "Copy Message",
                systemImage: "doc.on.doc"
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    contextCommits.map(\.message).joined(separator: "\n"),
                    forType: .string
                )
            }
            .disabled(contextCommits.isEmpty)
        }
    }
    
    // MARK: - Data Loading

    private func loadHistory(reset: Bool) async {
        let cacheKey = historyLoadKey
        if reset, let cached = historyCache[cacheKey] {
            await MainActor.run {
                applyCachedSnapshot(cached)
            }
            return
        }

        isLoading = true
        defer { isLoading = false }
        if reset {
            await MainActor.run {
                paging.reset()
                scrollTarget = nil
                rowFrames = [:]
                cancelHistoryRefreshIndicator()
                if commits.isEmpty {
                    graphModel = nil
                    selectedCommit = nil
                    fileChanges = []
                    selectedFile = nil
                    diffHunks = []
                } else {
                    scheduleHistoryRefreshIndicator()
                }
            }
        }
        let scope = Self.historyScope(branchFilter: appState.historyBranchFilter)
        let skip = await MainActor.run { paging.loadedCount }
        let pageSize = await MainActor.run { paging.pageSize }
        let searchQuery = activeHistorySearchQuery
        let newCommits: [Commit]
        if searchQuery.isEmpty {
            switch scope {
            case .allBranches:
                newCommits = await GitStatusService.shared.commitHistory(
                    allBranches: true,
                    limit: pageSize,
                    skip: skip,
                    in: repositoryURL
                )
            case .currentBranch:
                newCommits = await GitStatusService.shared.commitHistory(
                    allBranches: false,
                    limit: pageSize,
                    skip: skip,
                    in: repositoryURL
                )
            case .ref(let ref):
                newCommits = await GitStatusService.shared.commitHistory(
                    branch: ref,
                    limit: pageSize,
                    skip: skip,
                    in: repositoryURL
                )
            }
        } else {
            switch scope {
            case .allBranches:
                newCommits = await GitStatusService.shared.searchCommitHistory(
                    allBranches: true,
                    query: searchQuery,
                    limit: pageSize,
                    skip: skip,
                    in: repositoryURL
                )
            case .currentBranch:
                newCommits = await GitStatusService.shared.searchCommitHistory(
                    allBranches: false,
                    query: searchQuery,
                    limit: pageSize,
                    skip: skip,
                    in: repositoryURL
                )
            case .ref(let ref):
                newCommits = await GitStatusService.shared.searchCommitHistory(
                    branch: ref,
                    query: searchQuery,
                    limit: pageSize,
                    skip: skip,
                    in: repositoryURL
                )
            }
        }

        let newSelectedCommit: Commit?
        let newScrollTarget: String?
        switch scope {
        case .ref:
            newSelectedCommit = newCommits.first
            newScrollTarget = newCommits.first?.hash
        case .allBranches:
            if searchQuery.isEmpty,
               let selectedBranch,
               let tipHash = await GitStatusService.shared.tipHash(for: selectedBranch, in: repositoryURL),
               let tipCommit = newCommits.first(where: { $0.hash == tipHash }) {
                newSelectedCommit = tipCommit
                newScrollTarget = tipCommit.hash
            } else {
                newSelectedCommit = newCommits.first
                newScrollTarget = newCommits.first?.hash
            }
        case .currentBranch:
            newSelectedCommit = newCommits.first
            newScrollTarget = newCommits.first?.hash
        }

        let loadedCommits = await MainActor.run {
            if reset || skip == 0 {
                return newCommits
            }
            return commits + newCommits
        }
        let headHash: String?
        if let decoratedHead = Self.resolvedHeadHash(from: loadedCommits) {
            headHash = decoratedHead
        } else {
            headHash = await GitStatusService.shared.tipHash(
                for: "HEAD",
                in: repositoryURL
            )
        }
        await MainActor.run {
            currentHeadHash = headHash
        }
        let highlightRootHash = await Self.highlightRootHash(
            for: appState.historyBranchFilter,
            commits: loadedCommits,
            repositoryURL: repositoryURL
        )
        let highlighting = Self.highlighting(for: appState.historyBranchFilter)
        let newGraphModel = await CommitGraphGenerator.generateAsync(
            commits: loadedCommits,
            highlighting: highlighting,
            headHash: headHash,
            highlightRootHash: highlightRootHash
        )

        await MainActor.run {
            commits = loadedCommits
            graphModel = newGraphModel
            let visibleHashes = loadedCommits.map(\.hash)
            if skip == 0 {
                // A branch change must select that branch's tip, even when the
                // previously selected commit is also reachable from the new branch.
                commitSelection = HistoryCommitSelection()
            } else {
                commitSelection.prune(visibleHashes: visibleHashes)
            }
            if (skip == 0 || commitSelection.selectedHashes.isEmpty), let newSelectedCommit {
                commitSelection.select(
                    newSelectedCommit.hash,
                    modifiers: [],
                    visibleHashes: visibleHashes
                )
            }
            selectedCommit = Self.commit(withHash: commitSelection.primaryHash, in: loadedCommits)
            syncSelectedCommitSnapshot(from: loadedCommits)
            if skip == 0 {
                scrollTarget = Self.reloadTargetHash(
                    reset: true,
                    selectedCommitHash: selectedCommit?.hash,
                    newScrollTarget: newScrollTarget
                )
            }
            paging.finishLoadingMore(loaded: newCommits.count)
            cancelHistoryRefreshIndicator()

            historyCache[cacheKey] = HistorySnapshot(
                commits: loadedCommits,
                graphModel: newGraphModel,
                selectedCommitHash: selectedCommit?.hash
            )
        }
    }

    private var squashableCommits: [Commit] {
        historySelectionStore.selectedCommits
    }

    private func syncSelectedCommitSnapshot(from visibleCommits: [Commit]? = nil) {
        let source = visibleCommits ?? commits
        let commitsByHash = Dictionary(uniqueKeysWithValues: source.map { ($0.hash, $0) })
        historySelectionStore.selectedCommits = commitSelection.selectedHashes.compactMap { commitsByHash[$0] }
    }

    static func canSquashCommits(
        _ selectedCommits: [Commit],
        selectedHashes: [String],
        headHash: String?
    ) -> Bool {
        guard selectedCommits.count >= 2,
              selectedCommits.count == selectedHashes.count,
              selectedCommits.first?.hash == headHash,
              selectedCommits.allSatisfy({ !$0.isMerge }) else {
            return false
        }

        return zip(selectedCommits, selectedCommits.dropFirst()).allSatisfy { newer, older in
            newer.parents.first == older.hash
        }
    }

    private func applyCachedSnapshot(_ snapshot: HistorySnapshot) {
        cancelHistoryRefreshIndicator()
        paging.reset()
        paging.finishLoadingMore(loaded: snapshot.commits.count)
        scrollTarget = snapshot.selectedCommitHash
        rowFrames = [:]
        currentHeadHash = Self.resolvedHeadHash(from: snapshot.commits)

        commits = snapshot.commits
        graphModel = snapshot.graphModel

        let visibleHashes = snapshot.commits.map(\.hash)
        commitSelection.prune(visibleHashes: visibleHashes)
        if let cachedHash = snapshot.selectedCommitHash,
           snapshot.commits.contains(where: { $0.hash == cachedHash }) {
            commitSelection.select(cachedHash, modifiers: [], visibleHashes: visibleHashes)
        } else if commitSelection.selectedHashes.isEmpty, let first = snapshot.commits.first {
            commitSelection.select(first.hash, modifiers: [], visibleHashes: visibleHashes)
        }
        selectedCommit = Self.commit(withHash: commitSelection.primaryHash, in: snapshot.commits)
        syncSelectedCommitSnapshot(from: snapshot.commits)

        isLoading = false
        isRefreshingHistory = false
    }

    private func loadOlderHistoryIfNeeded() async {
        let shouldLoad = await MainActor.run {
            guard !isLoading else { return false }
            return paging.beginLoadingMore()
        }
        guard shouldLoad else { return }
        await loadHistory(reset: false)
    }
    
    private func loadFileChanges(for commit: Commit?) async {
        let loadID = UUID()
        await MainActor.run {
            commitFilesLoadID = loadID
            fileChanges = []
            selectedFile = nil
            diffHunks = []
            diffLoadID = UUID()
        }

        guard let commit = commit else {
            return
        }

        let changes = await GitStatusService.shared.changedFiles(
            in: commit.hash,
            in: repositoryURL
        )
        await MainActor.run {
            guard commitFilesLoadID == loadID,
                  selectedCommit?.hash == commit.hash else {
                return
            }
            fileChanges = changes
            selectedFile = changes.first
        }
    }
    
    private func loadDiff(for file: CommitFileChange?, in commit: Commit?) async {
        let loadID = UUID()
        await MainActor.run {
            diffLoadID = loadID
            diffHunks = []
        }

        guard let file = file, let commit = commit else {
            return
        }

        let hunks = await GitStatusService.shared.diff(
            for: file.path,
            in: commit.hash,
            in: repositoryURL
        )
        await MainActor.run {
            guard diffLoadID == loadID,
                  selectedCommit?.hash == commit.hash,
                  selectedFile == file else {
                return
            }
            diffHunks = hunks
        }
    }

    private func selectCommitForContextMenu(_ commit: Commit) {
        guard !commitSelection.selectedHashes.contains(commit.hash) else { return }

        selectedCommit = Self.selectCommitFromNativeTap(
            commit.hash,
            modifierFlags: [],
            commits: commits,
            selection: &commitSelection
        )
        syncSelectedCommitSnapshot()
    }
    
    private func performCheckoutCommit() async {
        guard let commit = pendingCommit else { return }
        do {
            try await GitStatusService.shared.checkoutCommit(
                commit.hash,
                force: discardLocalChanges,
                in: repositoryURL
            )
            await MainActor.run {
                pendingCommit = nil
                discardLocalChanges = false
                hasUncommittedChanges = false
                showingCheckoutConfirmation = false
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

    private func handleCommitDoubleClick(_ commit: Commit) {
        if let branchRef = HistoryCheckoutPolicy.branchRef(from: commit.refs) {
            onRequestCheckout(branchRef, false)
            return
        }

        pendingCommit = commit
        discardLocalChanges = false
        hasUncommittedChanges = false
        Task {
            let changeCount = await GitStatusService.shared.uncommittedChangeCount(in: repositoryURL)
            await MainActor.run {
                guard pendingCommit?.hash == commit.hash else { return }
                hasUncommittedChanges = changeCount > 0
                showingCheckoutConfirmation = true
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
            undoManager?.register(
                GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: label,
                    undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                    redoOperation: redoOperation
                )
            )
        }
    }
    
    private func performCherryPick(_ commits: [Commit]) async {
        guard !commits.isEmpty else { return }
        let hashes = commits.map(\.hash)

        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.cherryPickCommits(hashes, in: repositoryURL)
            await registerHeadChangingUndo(
                label: commits.count == 1
                    ? "Cherry-pick \(commits[0].hash.prefix(7))"
                    : "Cherry-pick \(commits.count) commits",
                oldHead: oldHead,
                redoOperation: commits.count == 1
                    ? .cherryPick(commit: commits[0].hash)
                    : .cherryPickCommits(commits: hashes)
            )
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await syncState?.refresh(repositoryURL: repositoryURL)
            let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
            let inProgress = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
            await MainActor.run {
                if hasConflicts {
                    errorMessage = "Cherry-pick produced conflicts. Resolve them in the File status view, then continue or abort."
                } else if inProgress != nil {
                    errorMessage = "Cherry-pick produced an empty commit. Open the File status view to skip or abort."
                } else {
                    errorMessage = error.localizedDescription
                }
                showingError = true
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        }
    }

    private func performMerge() async {
        guard let commit = pendingCommit else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.mergeCommit(
                commit.hash,
                noCommit: !mergeCommitImmediately,
                log: mergeIncludeMessages,
                in: repositoryURL
            )
            await registerHeadChangingUndo(
                label: "Merge \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redoOperation: .mergeCommit(
                    commit: commit.hash,
                    noCommit: !mergeCommitImmediately,
                    log: mergeIncludeMessages
                )
            )
            await MainActor.run {
                pendingCommit = nil
                showingMergeConfirmation = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performRebase() async {
        guard let commit = pendingCommit else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.rebaseCommit(commit.hash, in: repositoryURL)
            await registerHeadChangingUndo(
                label: "Rebase onto \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redoOperation: .rebaseOnto(commit: commit.hash)
            )
            await MainActor.run {
                pendingCommit = nil
                showingRebaseConfirmation = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performReset() async {
        guard let commit = pendingCommit else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.resetToCommit(commit.hash, mode: resetMode, in: repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Reset HEAD",
                            undoOperation: .resetHead(
                                target: oldHead,
                                mode: resetMode == .hard ? .hard : .soft,
                                expectedHead: newHead
                            ),
                            redoOperation: .resetHead(
                                target: commit.hash,
                                mode: resetMode.gitUndoMode,
                                expectedHead: oldHead
                            )
                        )
                    )
                }
            }
            await MainActor.run {
                pendingCommit = nil
                showingResetConfirmation = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performRevert() async {
        guard let commit = pendingCommit else { return }
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.revertCommit(commit.hash, in: repositoryURL)
            await registerHeadChangingUndo(
                label: "Revert \(commit.hash.prefix(7))",
                oldHead: oldHead,
                redoOperation: .revert(commit: commit.hash)
            )
            await MainActor.run {
                pendingCommit = nil
                showingRevertConfirmation = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await syncState?.refresh(repositoryURL: repositoryURL)
            let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
            let inProgress = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
            await MainActor.run {
                if hasConflicts {
                    errorMessage = "Revert produced conflicts. Resolve them in the File status view, then continue or abort."
                } else if inProgress != nil {
                    errorMessage = "Revert produced an empty commit. Open the File status view to skip or abort."
                } else {
                    errorMessage = error.localizedDescription
                }
                showingError = true
            }
            NotificationCenter.default.post(
                name: .repositoryDidChange,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        }
    }

    private func performSquash(commits: [Commit], message: String) async {
        guard Self.canSquashCommits(commits, selectedHashes: commits.map(\.hash), headHash: currentHeadHash) else {
            return
        }

        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.squashCommits(
                commits.map(\.hash),
                message: message,
                in: repositoryURL
            )
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Squash \(commits.count) commits",
                            undoOperation: .resetHead(target: oldHead, mode: .soft, expectedHead: newHead),
                            redoOperation: .commit(message: message, noVerify: false, signOff: false)
                        )
                    )
                }
            }
            await MainActor.run {
                squashSheetPresentation = nil
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performCreateTag() async {
        guard let commit = pendingCommit else { return }
        let name = tagNameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try await GitStatusService.shared.createTag(
                name: name,
                commit: commit.hash,
                annotated: false,
                message: nil,
                in: repositoryURL
            )
            await MainActor.run {
                tagNameInput = ""
                pendingCommit = nil
                showingTagSheet = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func performCreateBranch() async {
        guard let commit = pendingCommit else { return }
        let name = branchNameInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let support = GitBranchUndoSupport()
            let startPoint = try await support.tip(of: commit.hash, in: repositoryURL)
            _ = try await GitStatusService.shared.createBranch(
                name: name,
                checkout: checkoutNewBranch,
                commit: commit.hash,
                in: repositoryURL
            )
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Create branch \(name)",
                        undoOperation: .deleteLocalBranch(name: name, force: true, expectedTip: startPoint),
                        redoOperation: .createLocalBranch(name: name, startPoint: startPoint, checkout: checkoutNewBranch)
                    )
                )
                branchNameInput = ""
                checkoutNewBranch = true
                pendingCommit = nil
                showingBranchSheet = false
                NotificationCenter.default.post(
                    name: .repositoryDidChange,
                    object: nil,
                    userInfo: ["repositoryURL": repositoryURL]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private var historyLoadKey: String {
        "\(appState.historyBranchFilter.storageValue)|\(activeHistorySearchQuery)|\(historyLoadSizeRaw)"
    }

    private var activeHistorySearchQuery: String {
        debouncedHistorySearchText
    }

    enum HistoryScope {
        case allBranches
        case currentBranch
        case ref(String)
    }

    struct HistorySnapshot {
        let commits: [Commit]
        let graphModel: CommitGraphModel
        let selectedCommitHash: String?
    }

    static func historyScope(branchFilter: HistoryBranchFilter) -> HistoryScope {
        switch branchFilter {
        case .all:
            return .allBranches
        case .current:
            return .currentBranch
        case .branch(let branch):
            return .ref(branch)
        }
    }

    static func reloadTargetHash(
        reset: Bool,
        selectedCommitHash: String?,
        newScrollTarget: String?
    ) -> String? {
        reset ? (newScrollTarget ?? selectedCommitHash) : selectedCommitHash
    }

    static func highlighting(
        for branchFilter: HistoryBranchFilter
    ) -> CommitGraphHighlighting {
        branchFilter == .all ? .all : .currentBranchOnly
    }

    static func highlightRootHash(
        for branchFilter: HistoryBranchFilter,
        commits: [Commit],
        repositoryURL: URL
    ) async -> String? {
        switch branchFilter {
        case .all:
            return nil
        case .current:
            if let decoratedHead = resolvedHeadHash(from: commits) {
                return decoratedHead
            }
            return await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        case .branch(let branch):
            if let tipCommit = commits.first {
                return tipCommit.hash
            }
            return await GitStatusService.shared.tipHash(for: branch, in: repositoryURL)
        }
    }

    static func selectionModifiers(from flags: NSEvent.ModifierFlags) -> HistoryCommitSelection.Modifiers {
        var modifiers: HistoryCommitSelection.Modifiers = []
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }

    static func selectCommitFromNativeTap(
        _ hash: String,
        modifierFlags: NSEvent.ModifierFlags,
        commits: [Commit],
        selection: inout HistoryCommitSelection
    ) -> Commit? {
        selection.select(
            hash,
            modifiers: selectionModifiers(from: modifierFlags),
            visibleHashes: commits.map(\.hash)
        )
        return commit(withHash: selection.primaryHash, in: commits)
    }

    static func normalizedSearchQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return "" }
        return trimmed
    }

    private func scheduleHistorySearchDebounce(for query: String) {
        historySearchDebounceTask?.cancel()

        let normalizedQuery = Self.normalizedSearchQuery(query)
        guard !normalizedQuery.isEmpty else {
            debouncedHistorySearchText = ""
            return
        }

        historySearchDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            let debouncedQuery = Self.normalizedSearchQuery(query)
            await MainActor.run {
                debouncedHistorySearchText = debouncedQuery
            }
        }
    }

    static func resolvedHeadHash(from commits: [Commit]) -> String? {
        commits.first(where: { commit in
            commit.refs.contains {
                $0 == "HEAD" || $0.hasPrefix("HEAD -> ")
            }
        })?.hash
    }

    static func shouldAutoCenterCommit(
        targetHash: String,
        rowFrames: [String: CGRect],
        viewportHeight: CGFloat
    ) -> Bool {
        guard let frame = rowFrames[targetHash], viewportHeight > 0 else { return true }
        return !isRowVisible(frame, viewportHeight: viewportHeight)
    }

    static func isRowVisible(_ frame: CGRect, viewportHeight: CGFloat) -> Bool {
        frame.maxY > 0 && frame.minY < viewportHeight
    }

    static func commit(withHash hash: String?, in commits: [Commit]) -> Commit? {
        guard let hash else { return nil }
        return commits.first { $0.hash == hash }
    }

    static func contextMenuCommits(
        startingAt hash: String,
        commits: [Commit],
        selection: HistoryCommitSelection
    ) -> [Commit] {
        guard let clickedCommit = commit(withHash: hash, in: commits) else { return [] }
        guard selection.selectedHashes.contains(hash) else { return [clickedCommit] }

        let commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0) })
        let selectedCommits = selection.selectedHashes.compactMap { commitsByHash[$0] }
        guard selectedCommits.count == selection.selectedHashes.count else { return [] }
        return selectedCommits
    }

    static func cherryPickCommits(from contextMenuCommits: [Commit]) -> [Commit] {
        Array(contextMenuCommits.reversed())
    }

    static func draggedCommits(
        startingAt hash: String,
        commits: [Commit],
        selection: HistoryCommitSelection
    ) -> [GitDraggedCommit] {
        let commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.hash, $0) })
        return selection
            .draggedHashes(startingAt: hash, visibleHashes: commits.map(\.hash))
            .compactMap { selectedHash in
                guard let commit = commitsByHash[selectedHash] else { return nil }
                return GitDraggedCommit(
                    hash: commit.hash,
                    message: commit.message,
                    isMerge: commit.isMerge
                )
            }
    }

    private func makeCommitItemProvider(payload: GitDragPayload) -> NSItemProvider {
        GitDragPayloadStore.set(payload)

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
        return provider
    }

    private func updateCommitDragState(
        isActive: Bool,
        hashes: Set<String>,
        payload: GitDragPayload
    ) {
        let effectivePayload = activeCommitDragPayload ?? payload
        let payloadHashes = Set(effectivePayload.commits.map(\.hash))
        let effectiveHashes = payloadHashes.isEmpty ? hashes : payloadHashes

        if isActive, activeCommitDragPayload != nil {
            activeDragCommitHashes = effectiveHashes
        } else if activeDragCommitHashes == effectiveHashes || activeDragCommitHashes == hashes {
            finishCommitDrag(payload: effectivePayload, clearsPayload: true)
        }
    }

    private func beginCommitDrag(startingAt hash: String, payload: GitDragPayload) {
        dragClickSuppressionTask?.cancel()
        dragCompletionMonitorTask?.cancel()
        suppressedCommitClickHash = hash
        activeCommitDragPayload = payload
        dragCompletionMonitorTask = Task {
            while NSEvent.pressedMouseButtons & 1 != 0 {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            finishCommitDrag(payload: payload, clearsPayload: false)
        }
    }

    private func finishCommitDrag(payload: GitDragPayload, clearsPayload: Bool) {
        dragCompletionMonitorTask?.cancel()
        dragCompletionMonitorTask = nil
        activeDragCommitHashes.removeAll()
        if clearsPayload {
            GitDragPayloadStore.clear(ifMatching: payload)
        }
        if activeCommitDragPayload == payload {
            activeCommitDragPayload = nil
        }
        scheduleCommitClickSuppressionClear()
    }

    private func consumeSuppressedCommitClick(_ hash: String) -> Bool {
        guard suppressedCommitClickHash == hash else { return false }
        dragClickSuppressionTask?.cancel()
        suppressedCommitClickHash = nil
        return true
    }

    private func scheduleCommitClickSuppressionClear() {
        dragClickSuppressionTask?.cancel()
        dragClickSuppressionTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            suppressedCommitClickHash = nil
        }
    }

    @MainActor
    private func scheduleHistoryRefreshIndicator() {
        refreshIndicatorTask?.cancel()
        isRefreshingHistory = false
        refreshIndicatorTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isLoading && !commits.isEmpty {
                    isRefreshingHistory = true
                }
            }
        }
    }

    @MainActor
    private func cancelHistoryRefreshIndicator() {
        refreshIndicatorTask?.cancel()
        refreshIndicatorTask = nil
        isRefreshingHistory = false
    }
}

private extension ResetMode {
    var gitUndoMode: GitUndoResetMode {
        switch self {
        case .soft: return .soft
        case .mixed: return .mixed
        case .hard: return .hard
        }
    }
}

private struct CommitRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
