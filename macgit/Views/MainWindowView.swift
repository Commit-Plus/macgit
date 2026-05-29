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

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            Group {
                switch selectedItem {
                case .fileStatus:
                    FileStatusView(repositoryURL: repositoryURL)
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
        .sheet(isPresented: $showingCommitSheet) {
            CommitSheetView { message in
                Task {
                    await commitFromToolbar(message: message)
                }
            }
        }
    }

    @ViewBuilder
    private var leftToolbar: some View {
        if windowWidth > 1000 {
            HStack(spacing: 2) {
                toolbarButton(icon: "checkmark", label: "Commit", action: { showingCommitSheet = true })
                toolbarButton(icon: "arrow.down.to.line", label: "Pull", action: {})
                toolbarButton(icon: "arrow.up.to.line", label: "Push", action: {})
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", action: {})
                toolbarButton(icon: "arrow.triangle.branch", label: "Branch", action: {})
                toolbarButton(icon: "arrow.triangle.merge", label: "Merge", action: {})
                toolbarButton(icon: "archivebox", label: "Stash", action: {})
            }
        } else if windowWidth > 800 {
            HStack(spacing: 2) {
                toolbarButton(icon: "checkmark", label: "Commit", action: { showingCommitSheet = true })
                toolbarButton(icon: "arrow.down.to.line", label: "Pull", action: {})
                toolbarButton(icon: "arrow.up.to.line", label: "Push", action: {})
                toolbarButton(icon: "arrow.down.circle", label: "Fetch", action: {})
                moreMenu
            }
        } else {
            HStack(spacing: 2) {
                toolbarButton(icon: "checkmark", label: "Commit", action: { showingCommitSheet = true })
                moreMenu
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if windowWidth <= 800 {
                Button("Pull", action: {})
                Button("Push", action: {})
                Button("Fetch", action: {})
            }
            if windowWidth <= 1000 {
                Button("Branch", action: {})
                Button("Merge", action: {})
                Button("Stash", action: {})
            }
        } label: {
            ToolbarButtonLabel(icon: "ellipsis", label: "More")
        }
        .help("More Actions")
    }

    private func commitFromToolbar(message: String) async {
        // FileStatusView handles its own commit via the sheet it presents,
        // but the toolbar sheet is wired here. For now this is a no-op
        // since FileStatusView has its own commit logic.
    }
}

struct ToolbarButtonLabel: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
            Text(label)
                .font(.system(size: 9))
        }
        .frame(minWidth: 44)
    }
}

func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        ToolbarButtonLabel(icon: icon, label: label)
    }
    .help(label)
}

// MARK: - File Status View

struct FileStatusView: View {
    let repositoryURL: URL

    @State private var gitStatus: GitStatus = GitStatus(staged: [], unstaged: [], untracked: [])
    @State private var selectedFile: StatusFile? = nil
    @State private var diffHunks: [DiffHunk] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingCommitSheet = false

    private var changedFiles: [StatusFile] {
        gitStatus.unstaged + gitStatus.untracked
    }

    var body: some View {
        Group {
            if isLoading && gitStatus.isEmpty {
                ProgressView("Loading status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if gitStatus.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    message: "No changes",
                    detail: "Working directory is clean"
                )
            } else {
                HSplitView {
                    fileListPanel
                        .frame(minWidth: 220, idealWidth: 320, maxWidth: 500)

                    diffPanel
                        .frame(minWidth: 300)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadStatus()
        }
        .sheet(isPresented: $showingCommitSheet) {
            CommitSheetView { message in
                Task {
                    await commit(message: message)
                }
            }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
    }

    private var fileListPanel: some View {
        List(selection: $selectedFile) {
            if !gitStatus.staged.isEmpty {
                Section("Staged") {
                    ForEach(gitStatus.staged) { file in
                        fileRow(file: file, isStaged: true)
                            .tag(file)
                    }
                }
            }

            if !changedFiles.isEmpty {
                Section("Changed") {
                    ForEach(changedFiles) { file in
                        fileRow(file: file, isStaged: false)
                            .tag(file)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func fileRow(file: StatusFile, isStaged: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isStaged },
                set: { newValue in
                    Task {
                        if newValue {
                            await stage(file: file)
                        } else {
                            await unstage(file: file)
                        }
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: fileIcon(for: file))
                .foregroundStyle(fileColor(for: file))
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.system(size: 13, weight: .medium))
                if let original = file.originalPath {
                    Text("\(original) → \(file.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(file.directory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedFile = file
            Task {
                await loadDiff(for: file)
            }
        }
    }

    private var diffPanel: some View {
        Group {
            if let file = selectedFile {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: fileIcon(for: file))
                            .foregroundStyle(fileColor(for: file))
                        Text(file.path)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))

                    Divider()

                    if file.isImage {
                        imagePreview(file: file)
                    } else {
                        DiffView(hunks: diffHunks)
                    }
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

    private func imagePreview(file: StatusFile) -> some View {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        return Group {
            if let nsImage = NSImage(contentsOf: fileURL) {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: max(geo.size.width, CGFloat(nsImage.size.width)),
                                   maxHeight: max(geo.size.height, CGFloat(nsImage.size.height)))
                    }
                }
            } else {
                EmptyStateView(
                    icon: "photo",
                    message: "Unable to preview image",
                    detail: file.path
                )
            }
        }
    }

    private func fileIcon(for file: StatusFile) -> String {
        switch file.status {
        case .added:
            return "plus.circle.fill"
        case .staged:
            return "checkmark.circle.fill"
        case .modified:
            return "pencil.circle.fill"
        case .deleted:
            return "minus.circle.fill"
        case .renamed:
            return "arrow.right.circle.fill"
        case .untracked:
            return "questionmark.circle.fill"
        }
    }

    private func fileColor(for file: StatusFile) -> Color {
        switch file.status {
        case .added, .staged:
            return .green
        case .modified:
            return .orange
        case .deleted:
            return .red
        case .renamed:
            return .blue
        case .untracked:
            return .gray
        }
    }

    private func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        do {
            gitStatus = try await GitStatusService.shared.status(for: repositoryURL)
            if selectedFile == nil {
                if let first = gitStatus.staged.first ?? changedFiles.first {
                    selectedFile = first
                    await loadDiff(for: first)
                }
            } else {
                if let current = selectedFile,
                   gitStatus.staged.contains(where: { $0.path == current.path }) ||
                    changedFiles.contains(where: { $0.path == current.path }) {
                    await loadDiff(for: current)
                } else {
                    selectedFile = gitStatus.staged.first ?? changedFiles.first
                    if let file = selectedFile {
                        await loadDiff(for: file)
                    } else {
                        diffHunks = []
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func loadDiff(for file: StatusFile) async {
        do {
            diffHunks = try await GitStatusService.shared.diff(for: file, in: repositoryURL)
        } catch {
            diffHunks = []
        }
    }

    private func stage(file: StatusFile) async {
        do {
            try await GitStatusService.shared.stage(file: file, in: repositoryURL)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func unstage(file: StatusFile) async {
        do {
            try await GitStatusService.shared.unstage(file: file, in: repositoryURL)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func commit(message: String) async {
        do {
            try await GitStatusService.shared.commit(message: message, in: repositoryURL)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Other Views

struct HistoryView: View {
    let repositoryURL: URL

    var body: some View {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            message: "Commit history will appear here",
            detail: repositoryURL.path
        )
    }
}

struct SearchView: View {
    let repositoryURL: URL

    var body: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            message: "Search across commits, files, and branches",
            detail: repositoryURL.path
        )
    }
}

struct EmptyStateView: View {
    var icon: String = "rectangle.dashed"
    var message: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.title3)
                .foregroundStyle(.primary)
            if let detail = detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
