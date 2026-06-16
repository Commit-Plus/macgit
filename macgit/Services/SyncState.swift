//
//  SyncState.swift
//  macgit
//

import SwiftUI
import Combine

extension Notification.Name {
    static let repositoryDidChange = Notification.Name("macgit.repositoryDidChange")
}

class SyncState: ObservableObject {
    @Published var commitBadgeCount: Int = 0
    @Published var stagedBadgeCount: Int = 0
    @Published var stashableCount: Int = 0
    @Published var pushBadgeCount: Int = 0
    @Published var pullBadgeCount: Int = 0
    @Published var errorMessage: String? = nil
    @Published var showingError: Bool = false
    @Published var conflictMessage: String? = nil
    @Published var showingConflict: Bool = false
    @Published var infoMessage: String? = nil
    @Published var showingInfo: Bool = false
    @Published var isCommitting: Bool = false
    @Published var isPushing: Bool = false
    @Published var isPulling: Bool = false
    @Published var isFetching: Bool = false
    @Published var isMerging: Bool = false
    @Published var isStashing: Bool = false
    @Published var activeSyncBranch: String? = nil

    var isAnySyncing: Bool {
        isCommitting || isPushing || isPulling || isFetching || isMerging || isStashing
    }

    private var backgroundTask: Task<Void, Never>? = nil

    func refresh(repositoryURL: URL) async {
        do {
            let status = try await GitStatusService.shared.status(for: repositoryURL)
            let totalChanges = status.staged.count + status.unstaged.count + status.untracked.count
            let counts = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
            await MainActor.run {
                self.commitBadgeCount = totalChanges
                self.stagedBadgeCount = status.staged.count
                self.stashableCount = status.staged.count + status.unstaged.count
                self.pushBadgeCount = counts.ahead
                self.pullBadgeCount = counts.behind
            }
        } catch {
            // Silently ignore refresh failures to avoid spamming the user
        }
    }

    func startBackgroundSync(repositoryURL: URL, settings: RepoSettings) {
        stopBackgroundSync()
        backgroundTask = Task {
            while !Task.isCancelled {
                if settings.autoFetchEnabled {
                    try? await GitStatusService.shared.fetch(
                        options: GitStatusService.FetchOptions(),
                        in: repositoryURL
                    )
                }
                await refresh(repositoryURL: repositoryURL)
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            }
        }
    }

    func stopBackgroundSync() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    private func notifyRepositoryChanged(_ repositoryURL: URL) {
        NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
    }

    func showConflict(_ message: String) {
        conflictMessage = message
        showingConflict = true
    }

    func showInfo(_ message: String) {
        infoMessage = message
        showingInfo = true
    }

    func checkConflicts(repositoryURL: URL) async -> Bool {
        let hasConflicts = await GitStatusService.shared.hasConflicts(in: repositoryURL)
        if hasConflicts {
            showConflict("There are unresolved merge conflicts. Please resolve them before proceeding.")
        }
        return hasConflicts
    }

    func performPush(options: GitStatusService.PushOptions, repositoryURL: URL) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPushing = true }
        defer {
            Task { @MainActor in
                isPushing = false
                activeSyncBranch = nil
            }
        }
        do {
            await MainActor.run {
                activeSyncBranch = options.branches.count == 1 ? options.branches.first : nil
            }
            let output = try await GitStatusService.shared.push(options: options, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            let trimmed = output.lowercased()
            if trimmed.contains("everything up-to-date") || trimmed.contains("everything up to date") {
                showInfo("Everything up-to-date.")
            } else {
                showInfo("Push completed successfully.")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performPull(remote: String, branch: String, options: GitStatusService.PullOptions, repositoryURL: URL) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPulling = true }
        defer {
            Task { @MainActor in
                isPulling = false
                activeSyncBranch = nil
            }
        }
        do {
            await MainActor.run { activeSyncBranch = branch }
            let output = try await GitStatusService.shared.pull(remote: remote, branch: branch, options: options, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            let trimmed = output.lowercased()
            if trimmed.contains("already up to date") || trimmed.contains("already up-to-date") {
                showInfo("Already up to date.")
            } else {
                showInfo("Pull completed successfully.")
            }
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred during Pull. Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performPullBranch(branch: String, repositoryURL: URL) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPulling = true }
        defer {
            Task { @MainActor in
                isPulling = false
                activeSyncBranch = nil
            }
        }
        do {
            await MainActor.run { activeSyncBranch = branch }
            let output = try await GitStatusService.shared.pullBranchFromUpstream(branch: branch, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            let trimmed = output.lowercased()
            if trimmed.contains("already up to date") || trimmed.contains("already up-to-date") {
                showInfo("Already up to date.")
            } else {
                showInfo("Pull completed successfully.")
            }
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred during Pull. Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performFetch(options: GitStatusService.FetchOptions, repositoryURL: URL) async {
        await MainActor.run { isFetching = true }
        defer { Task { @MainActor in isFetching = false } }
        let before = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
        do {
            try await GitStatusService.shared.fetch(options: options, in: repositoryURL)
            let after = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            if after.behind <= before.behind {
                showInfo("No new changes on remote.")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performCommit(message: String, repositoryURL: URL) async {
        await MainActor.run { isCommitting = true }
        defer { Task { @MainActor in isCommitting = false } }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try await GitStatusService.shared.commit(message: message, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performMerge(branch: String, options: GitStatusService.MergeOptions, repositoryURL: URL) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isMerging = true }
        defer { Task { @MainActor in isMerging = false } }
        do {
            let output = try await GitStatusService.shared.merge(branch: branch, options: options, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            let trimmed = output.lowercased()
            if options.squash {
                showInfo("Squash merge completed. Changes are staged.")
            } else if trimmed.contains("already up to date") || trimmed.contains("already up-to-date") {
                showInfo("Already up to date.")
            } else {
                showInfo("Merge completed successfully.")
            }
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred during Merge. Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performStash(options: GitStatusService.StashOptions, repositoryURL: URL) async {
        await MainActor.run { isStashing = true }
        defer { Task { @MainActor in isStashing = false } }
        do {
            try await GitStatusService.shared.stash(options: options, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            showInfo("Changes stashed successfully.")
        } catch {
            showError(error.localizedDescription)
        }
    }
}
