//
//  FileStatusView.swift
//  macgit
//

import SwiftUI

struct FileStatusView: View {
    let repositoryURL: URL
    var syncState: SyncState? = nil

    @State private var gitStatus: GitStatus = GitStatus(staged: [], unstaged: [], untracked: [])
    @State private var selectedFile: StatusFile? = nil
    @State private var diffHunks: [DiffHunk] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false

    @State private var isCommitBarExpanded = false
    @State private var commitMessage = ""
    @State private var amendLastCommit = false
    @State private var bypassHooks = false
    @State private var signOffCommit = false
    @State private var pushAfterCommit = false
    @State private var commitAuthor: String?
    @State private var currentBranch: String?
    @State private var recentCommits: [(hash: String, message: String)] = []
    @State private var ignoreTargetFile: StatusFile? = nil
    @State private var conflictResolverWindow: NSWindow?

    private var changedFiles: [StatusFile] {
        gitStatus.unstaged + gitStatus.untracked
    }

    private var hasChanges: Bool {
        !gitStatus.isEmpty
    }

    private var canCommit: Bool {
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !gitStatus.staged.isEmpty
    }

    var body: some View {
        Group {
            if isLoading && !hasChanges {
                ProgressView("Loading status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasChanges {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    message: "No changes",
                    detail: "Working directory is clean"
                )
            } else {
                VStack(spacing: 0) {
                    PersistentHSplit(
                        autosaveName: "FileStatusMainSplit",
                        left: { fileListPanel.frame(minWidth: 220) },
                        right: { diffPanel.frame(minWidth: 300) }
                    )

                    commitBar
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadStatus()
        }
        .onChange(of: selectedFile) { _, newFile in
            if let file = newFile {
                Task {
                    await loadDiff(for: file)
                }
            } else {
                diffHunks = []
            }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .sheet(item: $ignoreTargetFile) { file in
            IgnoreOptionsView(
                file: file,
                repositoryURL: repositoryURL,
                onConfirm: { pattern in
                    Task {
                        await confirmIgnore(file: file, pattern: pattern)
                        ignoreTargetFile = nil
                    }
                },
                onCancel: {
                    ignoreTargetFile = nil
                }
            )
        }

        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await loadStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await loadStatus()
                }
            }
        }
    }

    private var fileListPanel: some View {
        List(selection: $selectedFile) {
            if !gitStatus.staged.isEmpty {
                Section {
                    ForEach(gitStatus.staged) { file in
                        fileRow(file: file, isStaged: true)
                            .tag(file)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text("Staged")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.none)
                        Spacer()
                        Button("Unstage All") {
                            Task { await unstageAll() }
                        }
                        .buttonStyle(GlassButtonStyle(tint: .yellow, fontSize: 10))
                    }
                    .padding(.horizontal, 4)
                }
            }

            if !changedFiles.isEmpty {
                Section {
                    ForEach(changedFiles) { file in
                        fileRow(file: file, isStaged: false)
                            .tag(file)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text("Changed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.none)
                        Spacer()
                        Button("Stage All") {
                            Task { await stageAll() }
                        }
                        .buttonStyle(GlassButtonStyle(tint: .accentColor, fontSize: 10))
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .listStyle(.inset)
    }

    private func fileRow(file: StatusFile, isStaged: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
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
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let original = file.originalPath {
                        Text("\(original) → \(file.path)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(file.directory)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedFile = file
            }

            moreButton(file: file, isStaged: isStaged)
                .padding(.trailing, 4)
        }
        .contextMenu {
            fileContextMenu(file: file, isStaged: isStaged)
        }
    }

    private func moreButton(file: StatusFile, isStaged: Bool) -> some View {
        Menu {
            Button("Open") { openFile(file: file) }
            Button("Show in Finder") { showInFinder(file: file) }
            Divider()

            if isStaged {
                Button("Unstage") { Task { await unstage(file: file) } }
                Button("Remove") { Task { await remove(file: file) } }
            } else {
                Button("Stage") { Task { await stage(file: file) } }
                Button("Discard") { Task { await discard(file: file) } }
                Button("Remove") { Task { await remove(file: file) } }
                if file.status == .untracked || file.status == .added {
                    Button("Ignore") { ignoreTargetFile = file }
                }
            }

            Divider()

            if !isStaged {
                Button("Reset") { Task { await discard(file: file) } }

                if !recentCommits.isEmpty {
                    Menu("Reset to Commit...") {
                        ForEach(recentCommits, id: \.hash) { commit in
                            Button("\(commit.hash) \(commit.message)") {
                                Task { await resetToCommit(file: file, commit: commit.hash) }
                            }
                        }
                    }
                }

                if file.status == .conflict {
                    Menu("Resolve Conflicts") {
                        Button("Use Current Version") {
                            Task { await resolveConflict(file: file, using: .ours) }
                        }
                        Button("Use Incoming Version") {
                            Task { await resolveConflict(file: file, using: .theirs) }
                        }
                        Button("Resolve Manually…") {
                            openConflictResolverWindow(for: file)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
    }

    @ViewBuilder
    private func fileContextMenu(file: StatusFile, isStaged: Bool) -> some View {
        Button("Open") { openFile(file: file) }
        Button("Show in Finder") { showInFinder(file: file) }
        Divider()

        if isStaged {
            Button("Unstage") { Task { await unstage(file: file) } }
            Button("Remove") { Task { await remove(file: file) } }
        } else {
            Button("Stage") { Task { await stage(file: file) } }
            Button("Discard") { Task { await discard(file: file) } }
            Button("Remove") { Task { await remove(file: file) } }
            if file.status == .untracked || file.status == .added {
                Button("Ignore") { ignoreTargetFile = file }
            }
        }

        Divider()

        if !isStaged {
            Button("Reset") { Task { await discard(file: file) } }

            if !recentCommits.isEmpty {
                Menu("Reset to Commit...") {
                    ForEach(recentCommits, id: \.hash) { commit in
                        Button("\(commit.hash) \(commit.message)") {
                            Task { await resetToCommit(file: file, commit: commit.hash) }
                        }
                    }
                }
            }

            if file.status == .conflict {
                Menu("Resolve Conflicts") {
                    Button("Use Current Version") {
                        Task { await resolveConflict(file: file, using: .ours) }
                    }
                    Button("Use Incoming Version") {
                        Task { await resolveConflict(file: file, using: .theirs) }
                    }
                    Button("Resolve Manually…") {
                        openConflictResolverWindow(for: file)
                    }
                }
            }
        }
    }

    private var diffPanel: some View {
        Group {
            if let file = selectedFile {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(for: file))
                            .foregroundStyle(fileColor(for: file))
                            .font(.system(size: 16, weight: .medium))
                        Text(file.path)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.separator)
                            .frame(height: 0.5)
                    }

                    if file.isImage {
                        imagePreview(file: file)
                    } else {
                        DiffView(
                            hunks: diffHunks,
                            file: file,
                            repositoryURL: repositoryURL,
                            onRefresh: {
                                Task {
                                    await loadStatus()
                                }
                            },
                            onError: { message in
                                errorMessage = message
                                showingError = true
                            }
                        )
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

    private var commitBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isCommitBarExpanded {
                expandedCommitBar
            } else {
                collapsedCommitBar
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private var collapsedCommitBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                TextField("Commit message", text: $commitMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .disabled(true)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 1, x: 0, y: 1)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCommitBarExpanded = true
                }
                Task {
                    if commitAuthor == nil {
                        commitAuthor = await GitStatusService.shared.gitUser(in: repositoryURL)
                    }
                    if currentBranch == nil {
                        currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var expandedCommitBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: author + options
            HStack(spacing: 10) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)

                Text(commitAuthor ?? "Committer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Menu {
                    Toggle("Amend last commit", isOn: $amendLastCommit)
                    Toggle("Bypass commit hooks", isOn: $bypassHooks)
                    Toggle("Sign off", isOn: $signOffCommit)
                } label: {
                    HStack(spacing: 4) {
                        Text("Commit Options")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(GlassButtonStyle(tint: .secondary, fontSize: 10))
            }

            // Message editor
            TextEditor(text: $commitMessage)
                .font(.system(size: 13))
                .lineSpacing(2)
                .frame(minHeight: 48, maxHeight: 100)
                .padding(6)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.separator.opacity(0.45), lineWidth: 0.5)
                )

            // Bottom row: toggles + buttons
            HStack(spacing: 12) {
                Toggle("Amend last commit", isOn: $amendLastCommit)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.checkbox)

                Toggle("Push changes immediately to \(currentBranch ?? "current branch")", isOn: $pushAfterCommit)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.checkbox)

                Spacer()

                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCommitBarExpanded = false
                    }
                }
                .buttonStyle(GlassButtonStyle(tint: .secondary, fontSize: 12))

                Button("Commit") {
                    Task {
                        await performCommit()
                    }
                }
                .buttonStyle(GlassProminentButtonStyle(tint: .accentColor, fontSize: 12))
                .disabled(!canCommit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func performCommit() async {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        do {
            try await GitStatusService.shared.commit(
                message: message,
                in: repositoryURL,
                amend: amendLastCommit,
                noVerify: bypassHooks,
                signOff: signOffCommit
            )
            if pushAfterCommit {
                let branch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
                let options = GitStatusService.PushOptions(remote: "origin", branches: [branch], pushTags: false)
                try await GitStatusService.shared.push(options: options, in: repositoryURL)
            }
            await MainActor.run {
                commitMessage = ""
                amendLastCommit = false
                bypassHooks = false
                signOffCommit = false
                pushAfterCommit = false
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCommitBarExpanded = false
                }
            }
            await loadStatus()
            if let syncState = syncState {
                await syncState.refresh(repositoryURL: repositoryURL)
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showingError = true
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
            return "pencil.circle.fill"
        case .modified:
            return "pencil.circle.fill"
        case .deleted:
            return "minus.circle.fill"
        case .renamed:
            return "arrow.right.circle.fill"
        case .untracked:
            return "questionmark.circle.fill"
        case .conflict:
            return "exclamationmark.triangle.fill"
        }
    }

    private func fileColor(for file: StatusFile) -> Color {
        switch file.status {
        case .added:
            return .green
        case .staged, .modified:
            return .orange
        case .deleted:
            return .red
        case .renamed:
            return .blue
        case .untracked:
            return .gray
        case .conflict:
            return .purple
        }
    }

    private func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        do {
            gitStatus = try await GitStatusService.shared.status(for: repositoryURL)
            recentCommits = await GitStatusService.shared.recentCommits(in: repositoryURL)

            if selectedFile == nil {
                selectedFile = gitStatus.staged.first ?? changedFiles.first
            } else {
                if let current = selectedFile,
                   let matched = gitStatus.staged.first(where: { $0.path == current.path }) ??
                                 changedFiles.first(where: { $0.path == current.path }) {
                    selectedFile = matched
                } else {
                    selectedFile = gitStatus.staged.first ?? changedFiles.first
                    if selectedFile == nil {
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
            await syncState?.refresh(repositoryURL: repositoryURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func unstage(file: StatusFile) async {
        do {
            try await GitStatusService.shared.unstage(file: file, in: repositoryURL)
            await loadStatus()
            await syncState?.refresh(repositoryURL: repositoryURL)
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

    private func stageAll() async {
        guard !changedFiles.isEmpty else { return }
        do {
            try await GitStatusService.shared.stageAll(files: changedFiles, in: repositoryURL)
            await loadStatus()
            await syncState?.refresh(repositoryURL: repositoryURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func unstageAll() async {
        guard !gitStatus.staged.isEmpty else { return }
        do {
            try await GitStatusService.shared.unstageAll(files: gitStatus.staged, in: repositoryURL)
            await loadStatus()
            await syncState?.refresh(repositoryURL: repositoryURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func showInFinder(file: StatusFile) {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }

    private func openFile(file: StatusFile) {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        NSWorkspace.shared.open(fileURL)
    }

    private func discard(file: StatusFile) async {
        do {
            try await GitStatusService.shared.discard(file: file, in: repositoryURL)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func remove(file: StatusFile) async {
        do {
            try await GitStatusService.shared.remove(file: file, in: repositoryURL)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func confirmIgnore(file: StatusFile, pattern: String) async {
        do {
            try await GitStatusService.shared.ignore(file: file, pattern: pattern, in: repositoryURL)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func resolveConflict(file: StatusFile, using: GitStatusService.ConflictResolution) async {
        do {
            try await GitStatusService.shared.resolveConflict(file: file, in: repositoryURL, using: using)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func resetToCommit(file: StatusFile, commit: String) async {
        do {
            try await GitStatusService.shared.resetToCommit(file: file, commit: commit, in: repositoryURL)
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func openConflictResolverWindow(for file: StatusFile) {
        // Close existing window if any
        conflictResolverWindow?.close()

        let allConflictFiles = (gitStatus.staged + gitStatus.unstaged + gitStatus.untracked)
            .filter { $0.status == .conflict }
            .reduce(into: [String: StatusFile]()) { dict, file in
                dict[file.path] = file
            }
            .values
            .sorted { $0.path < $1.path }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Resolve Conflicts"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let view = ConflictMergeToolView(
            allConflictFiles: allConflictFiles,
            repositoryURL: repositoryURL,
            onResolved: { [repositoryURL] in
                Task {
                    await loadStatus()
                    await syncState?.refresh(repositoryURL: repositoryURL)
                }
            },
            onClose: { [weak window] in
                window?.close()
            }
        )

        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)

        conflictResolverWindow = window
    }
}
