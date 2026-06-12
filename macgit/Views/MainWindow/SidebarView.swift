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
    let onRequestCheckout: (String) -> Void
    let onRequestPullBranch: (String) -> Void

    @State private var branchNodes: [BranchNode] = []
    @State private var currentBranch: String = ""
    @State private var branchSyncStatus: [String: BranchSyncStatus] = [:]
    @State private var expandedFolders: Set<String> = []
    @State private var isLoadingBranches = false
    @State private var tagNodes: [BranchNode] = []
    @State private var isLoadingTags = false
    @State private var expandedTagFolders: Set<String> = []

    // Section expansion states
    @State private var sectionStates: SidebarSectionState = SidebarSectionState()

    // Alerts
    @State private var errorMessage: String = ""
    @State private var showingError = false
    @State private var branchToDelete: String?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List(selection: $selection) {
            // WORKSPACE section
            Section(SidebarSection.workspace.rawValue) {
                ForEach(SidebarSection.workspace.items) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(SidebarSelection.item(item))
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

            // Other placeholder sections
            ForEach(SidebarSection.allCases.dropFirst(3), id: \.self) { section in
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { _ in
            Task {
                await loadBranches()
                await loadTags()
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

    // MARK: - Row Rendering

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
                        onRequestCheckout(row.fullPath)
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
                    onRequestCheckout(row.fullPath)
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
    private func syncBadge(for branch: String) -> some View {
        if let status = branchSyncStatus[branch] {
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

    // MARK: - Context Menu

    @ViewBuilder
    private func branchContextMenu(for branch: String) -> some View {
        Button("Checkout \(branch)") {
            onRequestCheckout(branch)
        }
        .disabled(branch == currentBranch)

        Divider()

        Button("Merge \(branch) into \(currentBranch)") {}
            .disabled(true)
        Button("Rebase current changes onto \(branch)") {}
            .disabled(true)

        Divider()

        Button("Fetch \(branch)") {
            onRequestPullBranch(branch)
        }
        .disabled(branchSyncStatus[branch]?.behind == 0)
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
        let tree = buildBranchTree(from: locals)
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

        await MainActor.run {
            branchNodes = tree
            currentBranch = current
            branchSyncStatus = syncMap
            print("[loadBranches] Updated branchSyncStatus with \(syncMap.count) entries")
            // Expand all folders by default on first load
            if expandedFolders.isEmpty {
                expandedFolders = allFolders
            }
        }
    }

    private func loadTags() async {
        isLoadingTags = true
        defer { isLoadingTags = false }
        let tags = await GitStatusService.shared.tags(in: repositoryURL)
        let tree = buildBranchTree(from: tags)
        let allFolders = collectFolderPaths(from: tree)
        await MainActor.run {
            tagNodes = tree
            if expandedTagFolders.isEmpty {
                expandedTagFolders = allFolders
            }
        }
    }

    // MARK: - Tree Builder

    private func buildBranchTree(from branches: [String], prefix: String = "") -> [BranchNode] {
        var groups = [String: [String]]()
        var leaves = Set<String>()

        for branch in branches {
            let relative = prefix.isEmpty ? branch : String(branch.dropFirst(prefix.count + 1))
            if let slashIndex = relative.firstIndex(of: "/") {
                let first = String(relative[..<slashIndex])
                let rest = String(relative[relative.index(after: slashIndex)...])
                let childBranch = prefix.isEmpty ? branch : "\(prefix)/\(rest)"
                groups[first, default: []].append(childBranch)
            } else {
                leaves.insert(relative)
            }
        }

        var nodes: [BranchNode] = []

        for (name, childBranches) in groups.sorted(by: { $0.key < $1.key }) {
            let fullPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            var children = buildBranchTree(from: childBranches, prefix: fullPath)
            if leaves.remove(name) != nil {
                children.insert(
                    BranchNode(name: name, fullPath: fullPath, isFolder: false, children: []),
                    at: 0
                )
            }
            nodes.append(BranchNode(name: name, fullPath: fullPath, isFolder: true, children: children))
        }

        for leaf in leaves.sorted() {
            let fullPath = prefix.isEmpty ? leaf : "\(prefix)/\(leaf)"
            nodes.append(BranchNode(name: leaf, fullPath: fullPath, isFolder: false, children: []))
        }

        return nodes
    }

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
        onRequestCheckout: { _ in },
        onRequestPullBranch: { _ in }
    )
}
