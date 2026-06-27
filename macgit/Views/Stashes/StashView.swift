//
//  StashView.swift
//  macgit
//

import SwiftUI

struct StashView: View {
    let repositoryURL: URL
    let stashRef: String

    @State private var fileChanges: [CommitFileChange] = []
    @State private var selectedFile: CommitFileChange? = nil
    @State private var diffHunks: [DiffHunk] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        Group {
            if isLoading && fileChanges.isEmpty {
                ProgressView("Loading stash…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if fileChanges.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    message: "No files in stash",
                    detail: "This stash does not contain any file changes"
                )
            } else {
                VStack(spacing: 0) {
                    stashHeader

                    PersistentHSplit(
                        autosaveName: "StashDetailSplit",
                        left: {
                            CommitFileListView(changes: fileChanges, selectedFile: $selectedFile)
                                .frame(minWidth: 220)
                        },
                        right: {
                            stashDiffPanel
                                .frame(minWidth: 300)
                        }
                    )
                }
            }
        }
        .id(stashRef)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: stashRef) {
            await loadStash(for: stashRef)
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
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            if let url = notification.userInfo?["repositoryURL"] as? URL, url == repositoryURL {
                Task {
                    await loadStash(for: stashRef)
                }
            }
        }
        .alert("Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
    }

    private var stashHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Stash")
                    .font(.system(size: 13, weight: .semibold))
                Text(stashRef)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(fileChanges.count) file\(fileChanges.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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

    private var stashDiffPanel: some View {
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
                        gitRef: stashRef
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

    private func loadStash(for ref: String) async {
        isLoading = true
        defer { isLoading = false }

        await MainActor.run {
            fileChanges = []
            selectedFile = nil
            diffHunks = []
        }

        let changes = await GitStatusService.shared.changedFiles(in: ref, in: repositoryURL)
        await MainActor.run {
            fileChanges = changes
            selectedFile = changes.first
        }
    }

    private func loadDiff(for file: CommitFileChange) async {
        let hunks = await GitStatusService.shared.diff(for: file.path, in: stashRef, in: repositoryURL)
        await MainActor.run {
            diffHunks = hunks
        }
    }
}

#Preview {
    StashView(repositoryURL: URL(fileURLWithPath: "/tmp"), stashRef: "stash@{0}")
}
