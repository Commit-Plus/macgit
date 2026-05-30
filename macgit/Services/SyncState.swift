//
//  SyncState.swift
//  macgit
//

import SwiftUI
import Combine

class SyncState: ObservableObject {
    @Published var commitBadgeCount: Int = 0
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

    var isAnySyncing: Bool {
        isCommitting || isPushing || isPulling || isFetching
    }

    private var backgroundTask: Task<Void, Never>? = nil

    func refresh(repositoryURL: URL) async {
        do {
            let status = try await GitStatusService.shared.status(for: repositoryURL)
            let totalChanges = status.staged.count + status.unstaged.count + status.untracked.count
            let counts = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
            await MainActor.run {
                self.commitBadgeCount = totalChanges
                self.pushBadgeCount = counts.ahead
                self.pullBadgeCount = counts.behind
            }
        } catch {
            // Silently ignore refresh failures to avoid spamming the user
        }
    }

    func startBackgroundSync(repositoryURL: URL) {
        stopBackgroundSync()
        backgroundTask = Task {
            while !Task.isCancelled {
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
        defer { Task { @MainActor in isPushing = false } }
        do {
            let output = try await GitStatusService.shared.push(options: options, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
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
        defer { Task { @MainActor in isPulling = false } }
        do {
            let output = try await GitStatusService.shared.pull(remote: remote, branch: branch, options: options, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
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

    func performFetch(repositoryURL: URL) async {
        await MainActor.run { isFetching = true }
        defer { Task { @MainActor in isFetching = false } }
        let before = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
        do {
            try await GitStatusService.shared.fetch(in: repositoryURL)
            let after = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
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
        } catch {
            showError(error.localizedDescription)
        }
    }
}
