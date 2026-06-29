//
//  SidebarView.swift
//  macgit
//
//  Created by Thanh Tran on 26/5/26.
//

import SwiftUI

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
    case search = "Search"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fileStatus: return "doc.text.magnifyingglass"
        case .history: return "clock.arrow.circlepath"
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
            return [.fileStatus, .history, .search]
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

struct BranchRowItem: Identifiable {
    let id: UUID
    let name: String
    let fullPath: String
    let isFolder: Bool
    let indent: Int
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

    let repositoryURL: URL
    @Binding var selection: SidebarSelection?
    let undoManager: GitUndoManager?
    let currentBranchFallbackSyncStatus: BranchSyncStatus?
    let isBranchSyncing: (String) -> Bool
    let onRequestCheckout: (String, Bool) -> Void
    let onRequestFetchBranch: (String) -> Void
    let onRequestApplyStash: (String) -> Void
    let onRequestDeleteStash: (String) -> Void
    let onRequestOpenWorktree: (URL) -> Void
    let onRequestOpenWorktreeInTerminal: (URL) -> Void
    let onRequestSearch: () -> Void
    let onRequestDragDrop: (GitDragDropRequest) -> Void

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
    @State private var branchToDelete: String?
    @State private var showingDeleteConfirmation = false
    @State private var activeDropTarget: GitDragTarget?
    @State private var activeDropLabel: String?
    @State private var isCurrentBranchDropTargeted = false

    init(
        repositoryURL: URL,
        selection: Binding<SidebarSelection?>,
        undoManager: GitUndoManager? = nil,
        currentBranchFallbackSyncStatus: BranchSyncStatus? = nil,
        isBranchSyncing: @escaping (String) -> Bool = { _ in false },
        onRequestCheckout: @escaping (String, Bool) -> Void,
        onRequestFetchBranch: @escaping (String) -> Void,
        onRequestApplyStash: @escaping (String) -> Void = { _ in },
        onRequestDeleteStash: @escaping (String) -> Void = { _ in },
        onRequestOpenWorktree: @escaping (URL) -> Void = { _ in },
        onRequestOpenWorktreeInTerminal: @escaping (URL) -> Void = { _ in },
        onRequestSearch: @escaping () -> Void = {},
        onRequestDragDrop: @escaping (GitDragDropRequest) -> Void = { _ in }
    ) {
        self.repositoryURL = repositoryURL
        self._selection = selection
        self.undoManager = undoManager
        self.currentBranchFallbackSyncStatus = currentBranchFallbackSyncStatus
        self.isBranchSyncing = isBranchSyncing
        self.onRequestCheckout = onRequestCheckout
        self.onRequestFetchBranch = onRequestFetchBranch
        self.onRequestApplyStash = onRequestApplyStash
        self.onRequestDeleteStash = onRequestDeleteStash
        self.onRequestOpenWorktree = onRequestOpenWorktree
        self.onRequestOpenWorktreeInTerminal = onRequestOpenWorktreeInTerminal
        self.onRequestSearch = onRequestSearch
        self.onRequestDragDrop = onRequestDragDrop
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
                } header: {
                    sectionHeader(.branches, isExpanded: sectionStates.branchesExpanded)
                }

                Section {
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
                } header: {
                    sectionHeader(.worktrees, isExpanded: sectionStates.worktreesExpanded)
                }

                Section {
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
                } header: {
                    sectionHeader(.tags, isExpanded: sectionStates.tagsExpanded)
                }

                Section {
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
                } header: {
                    sectionHeader(.remotes, isExpanded: sectionStates.remotesExpanded)
                }

                Section {
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
                } header: {
                    sectionHeader(.stashes, isExpanded: sectionStates.stashesExpanded)
                }

                // TODO: Re-enable when submodule/subtree support is implemented
                // ForEach([SidebarSection.submodules, .subtrees], id: \.self) { section in
                //     Section(section.rawValue) {
                //         Text("Coming soon")
                //             .font(.caption)
                //             .foregroundStyle(.secondary)
                //     }
                //     .disabled(true)
                // }
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
            .alert("Delete Branch", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let branch = branchToDelete {
                        Task { await deleteBranch(branch) }
                    }
                }
            } message: {
                Text("Are you sure you want to delete the branch '\(branchToDelete ?? "")'?")
            }
            .alert("Remove Worktree", isPresented: $showingWorktreeRemovalConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button(worktreeRemovalNeedsForce ? "Force Remove" : "Remove", role: .destructive) {
                    if let entry = pendingWorktreeRemoval {
                        Task { await removeWorktree(entry, force: worktreeRemovalNeedsForce) }
                    }
                }
            } message: {
                Text(worktreeRemovalMessage)
            }
            .alert("Force Switch Branch", isPresented: $showingWorktreeForceCheckoutConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingWorktreeForceCheckout = nil
                }
                Button("Force Switch", role: .destructive) {
                    if let entry = pendingWorktreeForceCheckout {
                        Task { await checkoutWorktree(entry, force: true) }
                    }
                }
            } message: {
                Text("This worktree has uncommitted changes. Force checkout and discard conflicting changes?")
            }
            .alert("Prune Worktrees", isPresented: $showingPruneWorktreesConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Prune", role: .destructive) {
                    Task { await pruneWorktrees() }
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

    @ViewBuilder
    private func sectionHeader(_ section: SidebarSection, isExpanded: Bool) -> some View {
        let isBranchesDropActive = section == .branches && activeDropTarget == .branchesHeader

        let baseView = HStack {
            Text(section.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if isBranchesDropActive, let activeDropLabel {
                Text(activeDropLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            if section == .worktrees {
                Button("Create Worktree", systemImage: "plus") {
                    Task { await prepareCreateWorktreeSheet() }
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

        if section == .branches {
            baseView
                .padding(.vertical, 2)
                .background(isBranchesDropActive ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onDropSessionUpdated { session in
                    updateDropHover(
                        target: .branchesHeader,
                        label: "Create Branch",
                        session: session
                    )
                }
                .dropDestination(for: GitDragPayload.self) { items, _ in
                    handleDrop(items, target: .branchesHeader)
                }
        } else {
            baseView
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

    private func updateDropHover(
        target: GitDragTarget,
        label: String,
        session: DropSession
    ) {
        switch session.phase {
        case .entering, .active:
            activeDropTarget = target
            activeDropLabel = label
        case .exiting, .dataTransferCompleted, .ended:
            if activeDropTarget == target {
                clearDropHover()
            }
        @unknown default:
            clearDropHover()
        }
    }

    private func clearDropHover() {
        activeDropTarget = nil
        activeDropLabel = nil
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
            onRequestDragDrop(request)
        case .reject(let reason):
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

        let baseView = HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16)
                }
            }

            if row.isFolder {
                Image(systemName: expandedFolders.contains(row.fullPath) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            } else if isCurrentBranch {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16, alignment: .center)
            } else {
                Color.clear
                    .frame(width: 16)
            }

            Text(row.name)
                .font(.system(size: 12))
                .fontWeight(isCurrentBranch && !row.isFolder ? .bold : .regular)
                .lineLimit(1)

            Spacer()

            if !row.isFolder {
                if isCurrentBranch {
                    headBadgeView
                }
                syncBadge(for: row.fullPath)
            }
        }
        .padding(.vertical, 2)
        .background(isActiveDropRow ? Color.accentColor.opacity(0.24) : Color.clear)
        .overlay {
            if isActiveDropRow {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
        }
        .overlay(alignment: .trailing) {
            if isActiveDropRow {
                Text(currentBranchDropLabel())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
        .contentShape(Rectangle())

        if row.isFolder {
            baseView
                .onTapGesture {
                    toggleFolder(row.fullPath)
                }
        } else {
            let rowView = baseView
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
                .draggable(
                    GitDragPayload.branch(
                        row.fullPath,
                        repositoryURL: repositoryURL
                    )
                )

            if isCurrentBranch {
                rowView
                    .onDrop(
                        of: [.macgitGitDragPayload],
                        isTargeted: $isCurrentBranchDropTargeted
                    ) { providers in
                        handleDrop(
                            providers,
                            target: branchTarget,
                            optionKeyPressed: NSEvent.modifierFlags.contains(.option)
                        )
                    }
            } else {
                rowView
            }
        }
    }

    private func currentBranchDropLabel() -> String {
        if NSEvent.modifierFlags.contains(.option) {
            return "Rebase or Cherry-pick"
        }
        return "Merge or Cherry-pick"
    }

    private var headBadgeView: some View {
        Text("HEAD")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5), in: Capsule())
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
                selection = .worktree(entry.path)
            }
            .onTapGesture(count: 2) {
                onRequestOpenWorktree(entry.path)
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
                    Button("Copy Tag Name to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(row.fullPath, forType: .string)
                    }
                }
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
            baseView
                .tag(SidebarSelection.remoteBranch(row.fullPath))
                .onTapGesture {
                    selection = .remoteBranch(row.fullPath)
                }
                .contextMenu {
                    Button("Copy Branch Name to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(row.fullPath, forType: .string)
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
            .contextMenu {
                Button("Apply stash") {
                    onRequestApplyStash(stash.ref)
                }
                Button("Delete stash", role: .destructive) {
                    onRequestDeleteStash(stash.ref)
                }
            }
    }

    @ViewBuilder
    private func syncBadge(for branch: String) -> some View {
        if isBranchSyncing(branch) {
            HStack(spacing: 0) {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 10)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary)
            .cornerRadius(4)
        } else if let status = SidebarBranchSyncBadgeResolver.status(
            for: branch,
            currentBranch: currentBranch,
            branchSyncStatus: branchSyncStatus,
            currentBranchFallbackSyncStatus: currentBranchFallbackSyncStatus
        ) {
            HStack(spacing: 4) {
                if status.ahead > 0 {
                    HStack(spacing: 2) {
                        Text("\(status.ahead)")
                        Text("↑")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary)
                    .cornerRadius(4)
                }

                if status.behind > 0 {
                    HStack(spacing: 2) {
                        Text("\(status.behind)")
                        Text("↓")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary)
                    .cornerRadius(4)
                }
            }
        }
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
    private func branchContextMenu(for branch: String) -> some View {
        Button("Checkout \(branch)") {
            onRequestCheckout(branch, false)
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Merge \(branch) into \(currentBranch)") {}
            .disabled(true)
        Button("Rebase current changes onto \(branch)") {}
            .disabled(true)

        Divider()

        Button("Fetch \(branch)") {
            onRequestFetchBranch(branch)
        }
        .disabled(!BranchFetchActionPolicy.shouldEnableFetch(for: branchSyncStatus[branch]))
        Menu("Push to") {
            Text("No remotes configured")
        }
        .disabled(true)
        Menu("Track Remote Branch") {
            Text("No remotes configured")
        }
        .disabled(true)

        Divider()

        Button("Diff Against Current") {}
            .disabled(true)

        Divider()

        Button("Rename...") {}
            .disabled(true)
        Button("Delete \(branch)") {
            branchToDelete = branch
            showingDeleteConfirmation = true
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Copy Branch Name to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch, forType: .string)
        }

        Divider()

        Button("Create Pull Request...") {}
            .disabled(true)
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
                Task { await clearWorktreeLabel(entry) }
            }
        }

        Divider()

        if !isCurrentRepositoryWorktree(entry) {
            if entry.isLocked {
                Button("Unlock Worktree") {
                    Task { await unlockWorktree(entry) }
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
                Task { await prepareCheckoutWorktreeSheet(for: entry) }
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
                        Task { await saveWorktreeLabel() }
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
                        Task { await lockWorktree(entry) }
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
                        Task { await moveWorktree(entry) }
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
                            Task { await checkoutWorktree(entry, force: false) }
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
                    Task { await createWorktree() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreateWorktree || isCreatingWorktree)
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 500)
    }

    private func deleteBranch(_ branch: String) async {
        do {
            let support = GitBranchUndoSupport()
            let tip = try await support.tip(of: branch, in: repositoryURL)
            let upstream = await support.upstream(of: branch, in: repositoryURL)
            _ = try await GitStatusService.shared.deleteBranch(name: branch, force: false, in: repositoryURL)

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
                        redoOperation: .deleteLocalBranch(name: branch, force: false, expectedTip: tip)
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
            expandedFolders = SidebarTreeBuilder.expandedFolderPaths(revealing: current)
                .intersection(allFolders)
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
        var branchesByRemote: [String: [String]] = [:]
        for remote in remotes {
            branchesByRemote[remote] = await GitStatusService.shared.remoteBranches(remote: remote, in: repositoryURL)
        }

        let tree = SidebarTreeBuilder.buildRemoteTree(remoteBranchesByRemote: branchesByRemote)
        await MainActor.run {
            remoteNodes = tree
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
        onRequestOpenWorktree: { _ in },
        onRequestOpenWorktreeInTerminal: { _ in }
    )
}
