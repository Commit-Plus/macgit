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

struct SidebarView: View {
    let repositoryURL: URL
    @Binding var selection: SidebarSelection?
    let isBranchSyncing: (String) -> Bool
    let onRequestCheckout: (String, Bool) -> Void
    let onRequestFetchBranch: (String) -> Void
    let onRequestApplyStash: (String) -> Void
    let onRequestDeleteStash: (String) -> Void
    let onRequestSearch: () -> Void

    @State private var branchNodes: [BranchNode] = []
    @State private var currentBranch: String = ""
    @State private var headHash: String = ""
    @State private var branchSyncStatus: [String: BranchSyncStatus] = [:]
    @State private var expandedFolders: Set<String> = []
    @State private var isLoadingBranches = false
    @State private var tagNodes: [BranchNode] = []
    @State private var isLoadingTags = false
    @State private var expandedTagFolders: Set<String> = []
    @State private var remoteNodes: [BranchNode] = []
    @State private var isLoadingRemotes = false
    @State private var expandedRemoteFolders: Set<String> = []
    @State private var stashEntries: [StashEntry] = []
    @State private var isLoadingStashes = false

    // Section expansion states
    @State private var sectionStates: SidebarSectionState = SidebarSectionState()

    // Alerts
    @State private var errorMessage: String = ""
    @State private var showingError = false
    @State private var branchToDelete: String?
    @State private var showingDeleteConfirmation = false

    init(
        repositoryURL: URL,
        selection: Binding<SidebarSelection?>,
        isBranchSyncing: @escaping (String) -> Bool = { _ in false },
        onRequestCheckout: @escaping (String, Bool) -> Void,
        onRequestFetchBranch: @escaping (String) -> Void,
        onRequestApplyStash: @escaping (String) -> Void = { _ in },
        onRequestDeleteStash: @escaping (String) -> Void = { _ in },
        onRequestSearch: @escaping () -> Void = {}
    ) {
        self.repositoryURL = repositoryURL
        self._selection = selection
        self.isBranchSyncing = isBranchSyncing
        self.onRequestCheckout = onRequestCheckout
        self.onRequestFetchBranch = onRequestFetchBranch
        self.onRequestApplyStash = onRequestApplyStash
        self.onRequestDeleteStash = onRequestDeleteStash
        self.onRequestSearch = onRequestSearch
    }

    var body: some View {
        List(selection: $selection) {
            // WORKSPACE section
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

            // BRANCHES section
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
                sectionHeader(SidebarSection.branches, isExpanded: sectionStates.branchesExpanded)
            }

            // TAGS section
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
                sectionHeader(SidebarSection.tags, isExpanded: sectionStates.tagsExpanded)
            }

            // REMOTES section
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
                sectionHeader(SidebarSection.remotes, isExpanded: sectionStates.remotesExpanded)
            }

            // STASHES section
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
                sectionHeader(SidebarSection.stashes, isExpanded: sectionStates.stashesExpanded)
            }

            // Other placeholder sections
            ForEach([SidebarSection.submodules, .subtrees], id: \.self) { section in
                Section(section.rawValue) {
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(true)
            }
        }
        .listStyle(.sidebar)
        .task {
            loadSectionStates()
            await loadBranches()
            await loadTags()
            await loadRemotes()
            await loadStashes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { _ in
            Task {
                await loadBranches()
                await loadTags()
                await loadRemotes()
                await loadStashes()
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
    }

    // MARK: - Section Header

    @ViewBuilder
    private func sectionHeader(_ section: SidebarSection, isExpanded: Bool) -> some View {
        HStack {
            Text(section.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
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
        let path = repositoryURL.path
        sectionStates = SidebarSettingsStore.shared.state(for: path)
    }

    private func toggleSection(_ section: SidebarSection) {
        let path = repositoryURL.path
        SidebarSettingsStore.shared.toggleSection(section, for: path)
        sectionStates = SidebarSettingsStore.shared.state(for: path)
    }

    // MARK: - Tree Flattening

    private var visibleBranchRows: [BranchRowItem] {
        var rows: [BranchRowItem] = []
        func traverse(_ nodes: [BranchNode], indent: Int) {
            for node in nodes {
                rows.append(BranchRowItem(
                    id: node.id,
                    name: node.name,
                    fullPath: node.fullPath,
                    isFolder: node.isFolder,
                    indent: indent
                ))
                if node.isFolder && expandedFolders.contains(node.fullPath) {
                    traverse(node.children, indent: indent + 1)
                }
            }
        }
        traverse(branchNodes, indent: 0)
        return rows
    }

    private var visibleTagRows: [BranchRowItem] {
        var rows: [BranchRowItem] = []
        func traverse(_ nodes: [BranchNode], indent: Int) {
            for node in nodes {
                rows.append(BranchRowItem(
                    id: node.id,
                    name: node.name,
                    fullPath: node.fullPath,
                    isFolder: node.isFolder,
                    indent: indent
                ))
                if node.isFolder && expandedTagFolders.contains(node.fullPath) {
                    traverse(node.children, indent: indent + 1)
                }
            }
        }
        traverse(tagNodes, indent: 0)
        return rows
    }

    private var visibleRemoteRows: [BranchRowItem] {
        var rows: [BranchRowItem] = []
        func traverse(_ nodes: [BranchNode], indent: Int) {
            for node in nodes {
                rows.append(BranchRowItem(
                    id: node.id,
                    name: node.name,
                    fullPath: node.fullPath,
                    isFolder: node.isFolder,
                    indent: indent
                ))
                if node.isFolder && expandedRemoteFolders.contains(node.fullPath) {
                    traverse(node.children, indent: indent + 1)
                }
            }
        }
        traverse(remoteNodes, indent: 0)
        return rows
    }

    // MARK: - Row Rendering

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
        let baseView = HStack(spacing: 4) {
            // Indentation
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16)
                }
            }

            // Icon
            if row.isFolder {
                Image(systemName: expandedFolders.contains(row.fullPath) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .center)
            } else {
                if row.fullPath == currentBranch {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16, alignment: .center)
                } else {
                    Color.clear
                        .frame(width: 16)
                }
            }

            // Name
            Text(row.name)
                .font(.system(size: 12))
                .fontWeight(row.fullPath == currentBranch && !row.isFolder ? .bold : .regular)
                .lineLimit(1)

            Spacer()

            // Sync badge
            if !row.isFolder {
                syncBadge(for: row.fullPath)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())

        if row.isFolder {
            baseView
                .onTapGesture {
                    toggleFolder(row.fullPath)
                }
        } else {
            baseView
                .tag(SidebarSelection.branch(row.fullPath))
                .onTapGesture {
                    selection = .branch(row.fullPath)
                }
                .onTapGesture(count: 2) {
                    if row.fullPath != currentBranch {
                        onRequestCheckout(row.fullPath, false)
                    }
                }
                .contextMenu {
                    branchContextMenu(for: row.fullPath)
                }
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
        } else if let status = branchSyncStatus[branch] {
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

    // MARK: - Context Menu

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

    // MARK: - Actions

    private func deleteBranch(_ branch: String) async {
        do {
            _ = try await GitStatusService.shared.deleteBranch(name: branch, force: false, in: repositoryURL)
            NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    // MARK: - Data Loading

    private func loadBranches() async {
        isLoadingBranches = true
        defer { isLoadingBranches = false }
        let locals = await GitStatusService.shared.localBranches(in: repositoryURL)
        let current = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
        // Filter out HEAD entries (e.g., from detached HEAD state)
        let filteredLocals = locals.filter { $0 != "HEAD" && !$0.contains("HEAD detached") }
        let tree = SidebarTreeBuilder.buildTree(from: filteredLocals)
        let allFolders = collectFolderPaths(from: tree)

        // Fetch sync status for each branch in parallel
        var syncMap: [String: BranchSyncStatus] = [:]
        print("[loadBranches] Fetching sync status for \(locals.count) branches")
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
                    print("[loadBranches] Got sync status for \(branch): ahead=\(status.ahead), behind=\(status.behind)")
                }
            }
        }
        print("[loadBranches] syncMap has \(syncMap.count) entries")

        // Fetch HEAD hash when in detached HEAD state
        var headHashValue: String = ""
        if current.isEmpty {
            let hash = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            if let hash = hash {
                headHashValue = String(hash.prefix(7))
            }
        }

        await MainActor.run {
            branchNodes = tree
            currentBranch = current
            headHash = headHashValue
            branchSyncStatus = syncMap
            print("[loadBranches] Updated branchSyncStatus with \(syncMap.count) entries")
            // Keep folders collapsed by default on first load
            if expandedFolders.isEmpty {
                expandedFolders = []
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
        var branchesByRemote: [String: [String]] = [:]
        for remote in remotes {
            branchesByRemote[remote] = await GitStatusService.shared.remoteBranches(remote: remote, in: repositoryURL)
        }
        let tree = SidebarTreeBuilder.buildRemoteTree(remoteBranchesByRemote: branchesByRemote)
        let allFolders = collectFolderPaths(from: tree)
        await MainActor.run {
            remoteNodes = tree
            // Keep folders collapsed by default on first load
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

    // MARK: - Tree Builder

    private func collectFolderPaths(from nodes: [BranchNode]) -> Set<String> {
        var paths = Set<String>()
        for node in nodes {
            if node.isFolder {
                paths.insert(node.fullPath)
                paths.formUnion(collectFolderPaths(from: node.children))
            }
        }
        return paths
    }
}

#Preview {
    SidebarView(
        repositoryURL: URL(fileURLWithPath: "/tmp"),
        selection: .constant(nil),
        isBranchSyncing: { _ in false },
        onRequestCheckout: { _, _ in },
        onRequestFetchBranch: { _ in }
    )
}
