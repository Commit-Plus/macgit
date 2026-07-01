//
//  FileStatusView.swift
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
import SwiftUI
import UniformTypeIdentifiers

struct FileStatusView: View {
    let repositoryURL: URL
    var syncState: SyncState? = nil
    var undoManager: GitUndoManager? = nil
    var onRequestApplyStash: (String) -> Void = { _ in }

    @State private var gitStatus: GitStatus = GitStatus(staged: [], unstaged: [], untracked: [])
    @State private var selectedFile: StatusFile? = nil
    @State private var selectedActionFileKeys: Set<FileStatusSelectionKey> = []
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

    private var actionSelection: FileStatusActionSelection {
        FileStatusActionSelection(
            selectedKeys: selectedActionFileKeys,
            stagedFiles: gitStatus.staged,
            changedFiles: changedFiles
        )
    }

    private func sectionCheckState(isStaged: Bool) -> NSControl.StateValue {
        let files = isStaged ? gitStatus.staged : changedFiles
        let allKeys = Set(files.map { FileStatusSelectionKey(file: $0, isStaged: isStaged) })
        let selected = selectedActionFileKeys.intersection(allKeys)
        if selected.isEmpty { return .off }
        if selected == allKeys { return .on }
        return .mixed
    }

    private func toggleSelectAll(isStaged: Bool, selectAll: Bool) {
        let files = isStaged ? gitStatus.staged : changedFiles
        let allKeys = Set(files.map { FileStatusSelectionKey(file: $0, isStaged: isStaged) })
        if selectAll {
            selectedActionFileKeys.formUnion(allKeys)
        } else {
            selectedActionFileKeys.subtract(allKeys)
        }
    }

    @ViewBuilder
    private var inProgressBanner: some View {
        if let operation = syncState?.inProgressOperation {
            let isEmpty = !hasChanges
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))

                Text(isEmpty ? operation.emptyMessage : operation.message)
                    .font(.system(size: 12))

                Spacer()

                HStack(spacing: 8) {
                    if isEmpty {
                        Button("Skip") {
                            Task { await skipInProgressOperation(operation) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Abort") {
                            Task { await abortInProgressOperation(operation) }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    } else {
                        Button("Abort") {
                            Task { await abortInProgressOperation(operation) }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        Button("Continue") {
                            Task { await continueInProgressOperation(operation) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.08))
            .overlay(
                Rectangle()
                    .fill(Color.orange.opacity(0.25))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private var hasInProgressOperation: Bool {
        syncState?.inProgressOperation != nil
    }

    var body: some View {
        Group {
            if isLoading && !hasChanges && !hasInProgressOperation {
                ProgressView("Loading status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasChanges && !hasInProgressOperation {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    message: "No changes",
                    detail: "Working directory is clean"
                )
            } else {
                VStack(spacing: 0) {
                    inProgressBanner

                    if hasChanges {
                        PersistentHSplit(
                            autosaveName: "FileStatusMainSplit",
                            left: { fileListPanel.frame(minWidth: 220) },
                            right: { diffPanel.frame(minWidth: 300) }
                        )

                        commitBar
                    } else {
                        EmptyStateView(
                            icon: "doc.text.magnifyingglass",
                            message: "No changes",
                            detail: "Working directory is clean"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            GitDragPayloadItemProviderLoader.load(from: provider) { result in
                Task { @MainActor in
                    if case .success(let payload) = result,
                       let stashRef = payload.stash {
                        onRequestApplyStash(stashRef)
                    }
                }
            }
            return true
        }
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
                        TriStateCheckbox(state: sectionCheckState(isStaged: true), accessibilityLabel: "Select all staged") { selectAll in
                            toggleSelectAll(isStaged: true, selectAll: selectAll)
                        }
                        Text("Staged")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.none)
                        Spacer()
                        Button(actionSelection.title(for: .staged)) {
                            Task {
                                if actionSelection.selectedStagedFiles.isEmpty {
                                    await unstageAll()
                                } else {
                                    await unstageSelected()
                                }
                            }
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
                        TriStateCheckbox(state: sectionCheckState(isStaged: false), accessibilityLabel: "Select all changed") { selectAll in
                            toggleSelectAll(isStaged: false, selectAll: selectAll)
                        }
                        Text("Changed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.none)
                        Spacer()
                        Button(actionSelection.title(for: .changed)) {
                            Task {
                                if actionSelection.selectedChangedFiles.isEmpty {
                                    await stageAll()
                                } else {
                                    await stageSelected()
                                }
                            }
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
        let selectionKey = FileStatusSelectionKey(file: file, isStaged: isStaged)
        let quickAction = FileStatusRowQuickAction(isStaged: isStaged)
        let dragPaths = actionSelection.dragPaths(startingAt: file, isStaged: isStaged)
        let dragPayload = GitDragPayload.files(dragPaths, repositoryURL: repositoryURL)

        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { selectedActionFileKeys.contains(selectionKey) },
                    set: { isSelected in
                        if isSelected {
                            selectedActionFileKeys.insert(selectionKey)
                        } else {
                            selectedActionFileKeys.remove(selectionKey)
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
            .onDrag {
                makeFileItemProvider(payload: dragPayload)
            } preview: {
                FileDragPreview(pathCount: dragPaths.count, fallbackPath: file.path)
            }

            quickActionButton(quickAction, file: file)
                .padding(.trailing, 2)

            moreButton(file: file, isStaged: isStaged)
                .padding(.trailing, 4)
        }
        .contextMenu {
            fileContextMenu(file: file, isStaged: isStaged)
        }
    }

    private func makeFileItemProvider(payload: GitDragPayload) -> NSItemProvider {
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
        provider.suggestedName = "\(payload.files.count) files"
        return provider
    }

    private func quickActionButton(_ quickAction: FileStatusRowQuickAction, file: StatusFile) -> some View {
        Button {
            Task {
                switch quickAction.kind {
                case .stage:
                    await stage(file: file)
                case .unstage:
                    await unstage(file: file)
                }
            }
        } label: {
            Image(systemName: quickAction.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(quickAction.accessibilityLabel)
        .accessibilityLabel(quickAction.accessibilityLabel)
        .frame(width: 24)
    }

    private func moreButton(file: StatusFile, isStaged: Bool) -> some View {
        let selection = actionSelection

        return Menu {
            Button("Open") { openFile(file: file) }
                .disabled(selection.isSingleFileActionDisabled)
            Button("Show in Finder") { showInFinder(file: file) }
                .disabled(selection.isSingleFileActionDisabled)
            Divider()

            if isStaged {
                Button(selection.title(for: .unstage)) {
                    Task {
                        await unstage(files: selection.files(for: .unstage, fallback: file))
                    }
                }
                Button(selection.title(for: .remove)) {
                    Task {
                        await remove(files: selection.files(for: .remove, fallback: file))
                    }
                }
            } else {
                Button(selection.title(for: .stage)) {
                    Task {
                        await stage(files: selection.files(for: .stage, fallback: file))
                    }
                }
                Button(selection.title(for: .discard)) {
                    Task {
                        await discard(files: selection.files(for: .discard, fallback: file))
                    }
                }
                Button(selection.title(for: .remove)) {
                    Task {
                        await remove(files: selection.files(for: .remove, fallback: file))
                    }
                }
                if file.status == .untracked || file.status == .added {
                    Button("Ignore") { ignoreTargetFile = file }
                        .disabled(selection.isSingleFileActionDisabled)
                }
            }

            Divider()

            if !isStaged {
                Button("Reset") { Task { await discard(file: file) } }
                    .disabled(selection.isSingleFileActionDisabled)

                if !recentCommits.isEmpty {
                    Menu("Reset to Commit...") {
                        ForEach(recentCommits, id: \.hash) { commit in
                            Button("\(commit.hash) \(commit.message)") {
                                Task { await resetToCommit(file: file, commit: commit.hash) }
                            }
                        }
                    }
                    .disabled(selection.isSingleFileActionDisabled)
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
                    .disabled(selection.isSingleFileActionDisabled)
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
        let selection = actionSelection

        Button("Open") { openFile(file: file) }
            .disabled(selection.isSingleFileActionDisabled)
        Button("Show in Finder") { showInFinder(file: file) }
            .disabled(selection.isSingleFileActionDisabled)
        Divider()

        if isStaged {
            Button(selection.title(for: .unstage)) {
                Task {
                    await unstage(files: selection.files(for: .unstage, fallback: file))
                }
            }
            Button(selection.title(for: .remove)) {
                Task {
                    await remove(files: selection.files(for: .remove, fallback: file))
                }
            }
        } else {
            Button(selection.title(for: .stage)) {
                Task {
                    await stage(files: selection.files(for: .stage, fallback: file))
                }
            }
            Button(selection.title(for: .discard)) {
                Task {
                    await discard(files: selection.files(for: .discard, fallback: file))
                }
            }
            Button(selection.title(for: .remove)) {
                Task {
                    await remove(files: selection.files(for: .remove, fallback: file))
                }
            }
            if file.status == .untracked || file.status == .added {
                Button("Ignore") { ignoreTargetFile = file }
                    .disabled(selection.isSingleFileActionDisabled)
            }
        }

        Divider()

        if !isStaged {
            Button("Reset") { Task { await discard(file: file) } }
                .disabled(selection.isSingleFileActionDisabled)

            if !recentCommits.isEmpty {
                Menu("Reset to Commit...") {
                    ForEach(recentCommits, id: \.hash) { commit in
                        Button("\(commit.hash) \(commit.message)") {
                            Task { await resetToCommit(file: file, commit: commit.hash) }
                        }
                    }
                }
                .disabled(selection.isSingleFileActionDisabled)
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
                .disabled(selection.isSingleFileActionDisabled)
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
                    } else if file.isVideo {
                        videoPreview(file: file)
                    } else {
                        DiffView(
                            hunks: diffHunks,
                            file: file,
                            repositoryURL: repositoryURL,
                            undoManager: undoManager,
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
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.commit(
                message: message,
                in: repositoryURL,
                amend: amendLastCommit,
                noVerify: bypassHooks,
                signOff: signOffCommit
            )
            let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            if !amendLastCommit, let oldHead, let newHead, oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntryFactory.commit(
                            repositoryURL: repositoryURL,
                            oldHead: oldHead,
                            newHead: newHead,
                            message: message,
                            noVerify: bypassHooks,
                            signOff: signOffCommit
                        )
                    )
                }
            }
            if pushAfterCommit {
                let branch = await GitStatusService.shared.currentBranch(in: repositoryURL) ?? ""
                let options = GitStatusService.PushOptions(remote: "origin", branches: [branch], pushTags: false)
                _ = try await GitStatusService.shared.push(options: options, in: repositoryURL)
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
                    ScrollView(.vertical) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, alignment: .top)
                            .clipped()
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

    private func videoPreview(file: StatusFile) -> some View {
        let fileURL = repositoryURL.appendingPathComponent(file.path)
        return VideoThumbnailView(fileURL: fileURL, filePath: file.path)
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

            selectedActionFileKeys = actionSelection.prunedSelection
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

    private func continueInProgressOperation(_ operation: GitInProgressOperation) async {
        do {
            switch operation {
            case .cherryPick:
                try await GitStatusService.shared.continueCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.continueRevert(in: repositoryURL)
            }
            await loadStatus()
            await syncState?.refresh(repositoryURL: repositoryURL)
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

    private func skipInProgressOperation(_ operation: GitInProgressOperation) async {
        do {
            switch operation {
            case .cherryPick:
                try await GitStatusService.shared.skipCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.skipRevert(in: repositoryURL)
            }
            await loadStatus()
            await syncState?.refresh(repositoryURL: repositoryURL)
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

    private func abortInProgressOperation(_ operation: GitInProgressOperation) async {
        do {
            switch operation {
            case .cherryPick:
                try await GitStatusService.shared.abortCherryPick(in: repositoryURL)
            case .revert:
                try await GitStatusService.shared.abortRevert(in: repositoryURL)
            }
            await loadStatus()
            await syncState?.refresh(repositoryURL: repositoryURL)
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

    private func stage(file: StatusFile) async {
        await stage(files: [file])
    }

    private func stage(files: [StatusFile]) async {
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        do {
            try await GitStatusService.shared.stageAll(files: files, in: repositoryURL)
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntryFactory.stageFiles(
                        repositoryURL: repositoryURL,
                        paths: paths
                    )
                )
            }
            await loadStatus()
            await syncState?.refresh(repositoryURL: repositoryURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func unstage(file: StatusFile) async {
        await unstage(files: [file])
    }

    private func unstage(files: [StatusFile]) async {
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        do {
            try await GitStatusService.shared.unstageAll(files: files, in: repositoryURL)
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntryFactory.unstageFiles(
                        repositoryURL: repositoryURL,
                        paths: paths
                    )
                )
            }
            await loadStatus()
            await syncState?.refresh(repositoryURL: repositoryURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func commit(message: String) async {
        do {
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.commit(message: message, in: repositoryURL)
            let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            if let oldHead, let newHead, oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntryFactory.commit(
                            repositoryURL: repositoryURL,
                            oldHead: oldHead,
                            newHead: newHead,
                            message: message,
                            noVerify: false,
                            signOff: false
                        )
                    )
                }
            }
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func stageAll() async {
        await stage(files: changedFiles)
    }

    private func unstageAll() async {
        await unstage(files: gitStatus.staged)
    }

    private func stageSelected() async {
        await stage(files: actionSelection.selectedChangedFiles)
    }

    private func unstageSelected() async {
        await unstage(files: actionSelection.selectedStagedFiles)
    }

    private func discard(files: [StatusFile]) async {
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        let snapshotStore = GitFileUndoSnapshotStore()
        do {
            let snapshot = try snapshotStore.capture(paths: paths, in: repositoryURL)
            for file in files {
                try await GitStatusService.shared.discard(file: file, in: repositoryURL)
            }
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: paths.count == 1 ? "Discard \((paths[0] as NSString).lastPathComponent)" : "Discard \(paths.count) files",
                        undoOperation: .restoreFileSnapshot(id: snapshot.id),
                        redoOperation: .discardFiles(paths: paths)
                    )
                )
            }
            await loadStatus()
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
        await discard(files: [file])
    }

    private func remove(files: [StatusFile]) async {
        guard !files.isEmpty else { return }
        let paths = files.map(\.path)
        let snapshotStore = GitFileUndoSnapshotStore()
        do {
            let snapshot = try snapshotStore.capture(paths: paths, in: repositoryURL)
            for file in files {
                try await GitStatusService.shared.remove(file: file, in: repositoryURL)
            }
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: paths.count == 1 ? "Remove \((paths[0] as NSString).lastPathComponent)" : "Remove \(paths.count) files",
                        undoOperation: .restoreFileSnapshot(id: snapshot.id),
                        redoOperation: .removeFiles(paths: paths)
                    )
                )
            }
            await loadStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func remove(file: StatusFile) async {
        await remove(files: [file])
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
