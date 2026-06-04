//
//  HistoryView.swift
//  macgit
//

import SwiftUI

struct HistoryView: View {
    let repositoryURL: URL
    let selectedBranch: String?
    
    @State private var commits: [Commit] = []
    @State private var graphLayout: CommitGraphLayout? = nil
    @State private var selectedCommit: Commit? = nil
    @State private var fileChanges: [CommitFileChange] = []
    @State private var selectedFile: CommitFileChange? = nil
    @State private var diffHunks: [DiffHunk] = []
    @State private var showAllBranches = true
    @State private var messageColumnWidth: CGFloat = 200
    @State private var authorColumnWidth: CGFloat = 120
    @State private var dateColumnWidth: CGFloat = 80
    @State private var commitColumnWidth: CGFloat = 70
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var scrollTarget: String? = nil
    
    init(repositoryURL: URL, selectedBranch: String? = nil) {
        self.repositoryURL = repositoryURL
        self.selectedBranch = selectedBranch
    }
    
    var body: some View {
        VStack(spacing: 0) {
            BranchFilterBar(
                showAllBranches: $showAllBranches,
                graphWidth: graphWidth,
                messageWidth: $messageColumnWidth,
                authorWidth: $authorColumnWidth,
                dateWidth: $dateColumnWidth,
                commitWidth: $commitColumnWidth
            ) {
                Task { await loadHistory() }
            }
            
            if isLoading && commits.isEmpty {
                ProgressView("Loading history…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commits.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    message: "No commits to display",
                    detail: "Repository may be empty"
                )
            } else {
                PersistentVSplit(
                    autosaveName: "HistoryMainSplit",
                    top: { commitGraphList.frame(minHeight: 200) },
                    bottom: { commitDetailPanel.frame(minHeight: 180) }
                )
            }
        }
        .id("history")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadHistory()
            if let branch = selectedBranch {
                await selectBranchTip(branch)
            }
        }
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
        .task(id: selectedBranch) {
            guard let branch = selectedBranch else { return }
            await selectBranchTip(branch)
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
    }
    
    // MARK: - Top Panel
    
    private var graphWidth: CGFloat {
        let maxLane = graphLayout?.laneCount ?? 1
        return CGFloat(maxLane) * 14 + 8
    }

    private var commitGraphList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    // Graph lines
                    if let layout = graphLayout {
                        BranchGraphCanvas(
                            nodes: layout.nodes,
                            edges: layout.edges,
                            laneCount: layout.laneCount
                        )
                        .padding(.leading, 4)
                    }

                    // Commit rows overlay
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let layout = graphLayout {
                            ForEach(Array(layout.nodes.enumerated()), id: \.element.id) { index, node in
                                CommitRowView(
                                    node: node,
                                    graphWidth: graphWidth,
                                    isSelected: selectedCommit?.hash == node.commit.hash,
                                    messageWidth: messageColumnWidth,
                                    authorWidth: authorColumnWidth,
                                    dateWidth: dateColumnWidth,
                                    commitWidth: commitColumnWidth
                                )
                                    .id(node.commit.hash)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedCommit = node.commit
                                    }
                                    .contextMenu {
                                        commitContextMenu(for: node.commit)
                                    }
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
        .id(showAllBranches)
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
                        repositoryURL: nil,
                        onRefresh: {},
                        onError: { _ in }
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
        Group {
            Button("Checkout Commit") {
                Task { await checkoutCommit(commit) }
            }
            Button("Cherry Pick") {
                Task { await cherryPickCommit(commit) }
            }
            Divider()
            Button("Copy Hash") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commit.hash, forType: .string)
            }
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commit.message, forType: .string)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let newCommits = await GitStatusService.shared.commitHistory(
                allBranches: showAllBranches,
                in: repositoryURL
            )
            await MainActor.run {
                commits = newCommits
                graphLayout = CommitGraphLayoutEngine.layout(commits: newCommits)
                if selectedCommit == nil, let first = newCommits.first {
                    selectedCommit = first
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func selectBranchTip(_ branch: String) async {
        // Wait up to 2 seconds for history to load if it hasn't yet
        var attempts = 0
        while graphLayout == nil && attempts < 40 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
        guard let tipHash = await GitStatusService.shared.tipHash(for: branch, in: repositoryURL) else { return }
        await MainActor.run {
            if let node = graphLayout?.nodes.first(where: { $0.commit.hash == tipHash }) {
                selectedCommit = node.commit
                scrollTarget = node.commit.hash
            }
        }
    }
    
    private func loadFileChanges(for commit: Commit?) async {
        guard let commit = commit else {
            await MainActor.run {
                fileChanges = []
                selectedFile = nil
                diffHunks = []
            }
            return
        }
        let changes = await GitStatusService.shared.changedFiles(
            in: commit.hash,
            in: repositoryURL
        )
        await MainActor.run {
            fileChanges = changes
            selectedFile = changes.first
        }
    }
    
    private func loadDiff(for file: CommitFileChange?, in commit: Commit?) async {
        guard let file = file, let commit = commit else {
            await MainActor.run {
                diffHunks = []
            }
            return
        }
        let hunks = await GitStatusService.shared.diff(
            for: file.path,
            in: commit.hash,
            in: repositoryURL
        )
        await MainActor.run {
            diffHunks = hunks
        }
    }
    
    private func checkoutCommit(_ commit: Commit) async {
        do {
            try await GitStatusService.shared.checkoutCommit(commit.hash, in: repositoryURL)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func cherryPickCommit(_ commit: Commit) async {
        do {
            try await GitStatusService.shared.cherryPickCommit(commit.hash, in: repositoryURL)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}
