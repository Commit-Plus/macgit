//
//  SyncState.swift
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
    @Published var inProgressOperation: GitInProgressOperation? = nil

    var isAnySyncing: Bool {
        isCommitting || isPushing || isPulling || isFetching || isMerging || isStashing
    }

    private var backgroundTask: Task<Void, Never>? = nil
    private var refreshGeneration = 0

    func refresh(repositoryURL: URL) async {
        let generation = await MainActor.run { () -> Int in
            refreshGeneration += 1
            return refreshGeneration
        }

        let uncommittedCount = await GitStatusService.shared.uncommittedChangeCount(in: repositoryURL)
        let trackedCounts = await GitStatusService.shared.trackedStatusCounts(in: repositoryURL)
        await MainActor.run {
            guard generation == refreshGeneration else { return }
            self.commitBadgeCount = uncommittedCount
            self.stagedBadgeCount = trackedCounts.staged
            self.stashableCount = trackedCounts.staged + trackedCounts.unstaged
        }

        let counts = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
        let operation = await GitStatusService.shared.inProgressOperation(in: repositoryURL)
        await MainActor.run {
            // A checkout or another repository change can start a newer
            // refresh while this one is still reading Git state. Never let
            // the older snapshot overwrite the newer one.
            guard generation == refreshGeneration else { return }
            self.pushBadgeCount = counts.ahead
            self.pullBadgeCount = counts.behind
            self.inProgressOperation = operation
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

    func performPush(
        options: GitStatusService.PushOptions,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPushing = true }
        defer {
            Task { @MainActor in
                isPushing = false
                activeSyncBranch = nil
            }
        }

        let remoteSupport = GitRemoteUndoSupport()
        var unpublishedBranches: [(local: String, remote: String)] = []
        for local in options.branches {
            let remoteBranch = options.branchMappings[local] ?? local
            guard !local.isEmpty, !remoteBranch.isEmpty else { continue }
            do {
                let existingHash = try await remoteSupport.remoteHash(remote: options.remote, branch: remoteBranch, in: repositoryURL)
                if existingHash == nil {
                    unpublishedBranches.append((local, remoteBranch))
                }
            } catch {
                // Pre-flight check failed; skip undo registration for this branch to avoid misclassifying it as new.
                continue
            }
        }

        do {
            await MainActor.run {
                activeSyncBranch = options.branches.count == 1 ? options.branches.first : nil
            }
            let output = try await GitStatusService.shared.push(
                options: options,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            for mapping in unpublishedBranches {
                if let remoteHash = try await remoteSupport.remoteHash(remote: options.remote, branch: mapping.remote, in: repositoryURL) {
                    await MainActor.run {
                        undoManager?.register(
                            GitUndoEntry(
                                repositoryURL: repositoryURL,
                                label: "Publish \(options.remote)/\(mapping.remote)",
                                undoOperation: .deleteRemoteBranch(remote: options.remote, branch: mapping.remote, expectedHash: remoteHash),
                                redoOperation: .pushBranch(remote: options.remote, localBranch: mapping.local, remoteBranch: mapping.remote),
                                confirmationMessage: "Undoing publish will delete '\(options.remote)/\(mapping.remote)' from the remote. Continue?"
                            )
                        )
                    }
                }
            }
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

    func performTrackRemoteBranch(branch: String, upstream: String?, repositoryURL: URL) async {
        do {
            if let upstream {
                try await GitStatusService.shared.setUpstream(upstream: upstream, branch: branch, in: repositoryURL)
                await refresh(repositoryURL: repositoryURL)
                notifyRepositoryChanged(repositoryURL)
                showInfo("Tracking \(upstream) for \(branch).")
            } else {
                try await GitStatusService.shared.unsetUpstream(branch: branch, in: repositoryURL)
                await refresh(repositoryURL: repositoryURL)
                notifyRepositoryChanged(repositoryURL)
                showInfo("Stopped tracking upstream for \(branch).")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performPull(
        remote: String,
        branch: String,
        options: GitStatusService.PullOptions,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPulling = true }
        defer {
            Task { @MainActor in
                isPulling = false
                activeSyncBranch = nil
            }
        }
        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        do {
            await MainActor.run { activeSyncBranch = branch }
            let output = try await GitStatusService.shared.pull(
                remote: remote,
                branch: branch,
                options: options,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Pull",
                            undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                            redoOperation: .resetHead(target: newHead, mode: .hard, expectedHead: oldHead),
                            confirmationMessage: "Undoing a pull will reset the current branch back to its previous commit. Continue?"
                        )
                    )
                }
            }
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

    func performPullBranch(
        branch: String,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        await MainActor.run { isPulling = true }
        defer {
            Task { @MainActor in
                isPulling = false
                activeSyncBranch = nil
            }
        }
        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        do {
            await MainActor.run { activeSyncBranch = branch }
            let output = try await GitStatusService.shared.pullBranchFromUpstream(
                branch: branch,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Pull",
                            undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                            redoOperation: .resetHead(target: newHead, mode: .hard, expectedHead: oldHead),
                            confirmationMessage: "Undoing a pull will reset the current branch back to its previous commit. Continue?"
                        )
                    )
                }
            }
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

    func performPushToTracked(
        branch: String,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
            showError("Branch '\(branch)' has no upstream to push to.")
            return
        }
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            showError("Could not parse upstream '\(upstream)'.")
            return
        }
        let options = GitStatusService.PushOptions(
            remote: parts[0],
            branches: [branch],
            branchMappings: [branch: parts[1]]
        )
        await performPush(
            options: options,
            repositoryURL: repositoryURL,
            undoManager: undoManager,
            credentialResolver: credentialResolver
        )
    }

    func performRebaseOnto(branch: String, repositoryURL: URL, undoManager: GitUndoManager? = nil) async {
        if await checkConflicts(repositoryURL: repositoryURL) { return }
        let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
        do {
            try await GitStatusService.shared.rebaseCommit(branch, in: repositoryURL)
            if let oldHead,
               let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL),
               oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntry(
                            repositoryURL: repositoryURL,
                            label: "Rebase onto \(branch)",
                            undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                            redoOperation: .rebaseOnto(commit: branch)
                        )
                    )
                }
            }
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            showInfo("Rebased current branch onto \(branch).")
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred during Rebase. Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performFetch(
        options: GitStatusService.FetchOptions,
        repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        await MainActor.run { isFetching = true }
        defer { Task { @MainActor in isFetching = false } }
        let before = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
        do {
            try await GitStatusService.shared.fetch(
                options: options,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            let after = await GitStatusService.shared.aheadBehindCount(in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            if after.behind > 0 {
                showInfo("Fetch completed. Current branch is still \(after.behind) commit\(after.behind == 1 ? "" : "s") behind its upstream. Pull to update the local branch.")
            } else if after.behind <= before.behind {
                showInfo("No new changes on remote.")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performFetchBranch(
        branch: String,
        repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        await MainActor.run { isFetching = true }
        defer { Task { @MainActor in isFetching = false } }
        guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
            showError("Branch '\(branch)' has no upstream to fetch from.")
            return
        }
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else {
            showError("Could not parse upstream '\(upstream)'.")
            return
        }
        let before = await GitStatusService.shared.branchSyncStatus(for: branch, in: repositoryURL)
        do {
            try await GitStatusService.shared.fetchBranch(
                remote: parts[0],
                branch: parts[1],
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            let after = await GitStatusService.shared.branchSyncStatus(for: branch, in: repositoryURL)
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            if let after, after.behind > 0 {
                showInfo("Fetch completed. \(branch) is still \(after.behind) commit\(after.behind == 1 ? "" : "s") behind \(upstream). Pull to update the local branch.")
            } else if (after?.behind ?? 0) <= (before?.behind ?? 0) {
                showInfo("No new changes on remote.")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    func performFetchAndFastForwardBranch(
        branch: String,
        repositoryURL: URL,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async {
        await MainActor.run {
            isFetching = true
            activeSyncBranch = branch
        }
        defer {
            Task { @MainActor in
                isFetching = false
                activeSyncBranch = nil
            }
        }
        do {
            let output = try await GitStatusService.shared.fetchAndFastForwardBranchFromUpstream(
                branch: branch,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            let trimmed = output.lowercased()
            if trimmed.contains("already up to date") || trimmed.contains("already up-to-date") {
                showInfo("Already up to date.")
            } else {
                showInfo("Fetched and updated \(branch).")
            }
        } catch {
            let message = error.localizedDescription
            if message.uppercased().contains("CONFLICT") {
                showConflict("Merge conflicts occurred while updating \(branch). Please resolve them in the File status view.")
            } else {
                showError(message)
            }
        }
    }

    func performCommit(
        message: String,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil,
        noVerify: Bool = false,
        signOff: Bool = false,
        commitAllChanges: Bool = false
    ) async {
        await MainActor.run { isCommitting = true }
        defer { Task { @MainActor in isCommitting = false } }
        do {
            if commitAllChanges {
                try await GitStatusService.shared.stageAllChanges(in: repositoryURL)
            }
            let oldHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            try await GitStatusService.shared.commit(
                message: message,
                in: repositoryURL,
                noVerify: noVerify,
                signOff: signOff
            )
            let newHead = await GitStatusService.shared.tipHash(for: "HEAD", in: repositoryURL)
            if let oldHead, let newHead, oldHead != newHead {
                await MainActor.run {
                    undoManager?.register(
                        GitUndoEntryFactory.commit(
                            repositoryURL: repositoryURL,
                            oldHead: oldHead,
                            newHead: newHead,
                            message: message,
                            noVerify: noVerify,
                            signOff: signOff
                        )
                    )
                }
            }
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

    func performStash(
        options: GitStatusService.StashOptions,
        repositoryURL: URL,
        undoManager: GitUndoManager? = nil
    ) async {
        await MainActor.run { isStashing = true }
        defer { Task { @MainActor in isStashing = false } }
        do {
            try await GitStatusService.shared.stash(options: options, in: repositoryURL)
            let support = GitStashUndoSupport()
            let hash = try await support.hash(for: "stash@{0}", in: repositoryURL)
            await MainActor.run {
                undoManager?.register(
                    GitUndoEntry(
                        repositoryURL: repositoryURL,
                        label: "Stash changes",
                        undoOperation: .stashApplyAndDrop(hash: hash),
                        redoOperation: .stashPush(
                            message: options.message,
                            keepIndex: options.keepIndex,
                            paths: options.paths,
                            includeUntracked: options.includeUntracked
                        )
                    )
                )
            }
            await refresh(repositoryURL: repositoryURL)
            notifyRepositoryChanged(repositoryURL)
            showInfo("Changes stashed successfully.")
        } catch {
            showError(error.localizedDescription)
        }
    }
}
