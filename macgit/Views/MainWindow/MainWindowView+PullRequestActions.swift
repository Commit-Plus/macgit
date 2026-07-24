//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

extension MainWindowView {
    func openPullRequest(branch: String) async {
        guard let upstream = await GitStatusService.shared.upstreamBranch(for: branch, in: repositoryURL) else {
            await MainActor.run {
                syncState.showError("Branch '\(branch)' has no upstream. Push it first to create a pull request.")
            }
            return
        }
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else {
            await MainActor.run {
                syncState.showError("Could not parse upstream '\(upstream)'.")
            }
            return
        }
        let remoteName = parts[0]
        let remoteBranch = parts[1]
        let remoteURL = await GitStatusService.shared.remoteURL(remote: remoteName, in: repositoryURL)
        guard let url = PullRequestURLBuilder.build(remoteURL: remoteURL, branch: remoteBranch) else {
            await MainActor.run {
                syncState.showError("Remote '\(remoteName)' is not a recognized pull request host (GitHub, GitLab, or Bitbucket).")
            }
            return
        }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    func prepareCreatePullRequest(branch: String) async {
        do {
            let remote = try await prepareRemoteBranchForPullRequest(branch: branch)
            await pullRequestController.loadPullRequests(repositoryURL: repositoryURL, remoteName: remote)
            if let errorMessage = pullRequestController.errorMessage {
                await MainActor.run {
                    syncState.showError(errorMessage)
                }
                return
            }
            await pullRequestController.presentCreatePullRequest(sourceBranch: branch)
            if pullRequestController.createDraftSeed == nil,
               let detailErrorMessage = pullRequestController.detailErrorMessage {
                await MainActor.run {
                    syncState.showError(detailErrorMessage)
                    pullRequestController.detailErrorMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                syncState.showError(error.localizedDescription)
            }
        }
    }

    func prepareRemoteBranchForPullRequest(branch: String) async throws -> String {
        let localBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !localBranch.isEmpty else {
            throw GitError.commandFailed("Branch name is required.")
        }

        if let upstream = await GitStatusService.shared.upstreamBranch(for: localBranch, in: repositoryURL) {
            let remoteBranch = try parseRemoteBranch(upstream)
            if let status = await GitStatusService.shared.branchSyncStatus(for: localBranch, in: repositoryURL) {
                if status.behind > 0 {
                    throw GitError.commandFailed("Branch '\(localBranch)' is behind '\(upstream)'. Pull or rebase it before creating a pull request.")
                }
                if status.ahead > 0 {
                    try await pushBranchForPullRequest(
                        localBranch: localBranch,
                        remote: remoteBranch.remote,
                        remoteBranch: remoteBranch.branch,
                        setUpstream: false
                    )
                }
            }
            return remoteBranch.remote
        }

        let remote = try await defaultPullRequestRemote()
        try await pushBranchForPullRequest(
            localBranch: localBranch,
            remote: remote,
            remoteBranch: localBranch,
            setUpstream: true
        )
        return remote
    }

    func defaultPullRequestRemote() async throws -> String {
        let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
        guard !remotes.isEmpty else {
            throw GitError.commandFailed("No remotes configured. Add a remote before creating a pull request.")
        }
        if let preferred = repoSettings.defaultRemoteName, remotes.contains(preferred) {
            return preferred
        }
        return remotes.first(where: { $0 == "origin" }) ?? remotes[0]
    }

    func parseRemoteBranch(_ upstream: String) throws -> (remote: String, branch: String) {
        let parts = upstream.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw GitError.commandFailed("Could not parse upstream '\(upstream)'.")
        }
        return (parts[0], parts[1])
    }

    func pushBranchForPullRequest(
        localBranch: String,
        remote: String,
        remoteBranch: String,
        setUpstream: Bool
    ) async throws {
        await MainActor.run {
            syncState.isPushing = true
            syncState.activeSyncBranch = localBranch
        }
        defer {
            Task { @MainActor in
                syncState.isPushing = false
                syncState.activeSyncBranch = nil
            }
        }

        let options = GitStatusService.PushOptions(
            remote: remote,
            branches: [localBranch],
            branchMappings: [localBranch: remoteBranch]
        )
        _ = try await GitStatusService.shared.push(
            options: options,
            in: repositoryURL,
            credentialResolver: providerAccountController.credentialResolver()
        )
        if setUpstream {
            try await GitStatusService.shared.setUpstream(
                upstream: "\(remote)/\(remoteBranch)",
                branch: localBranch,
                in: repositoryURL
            )
        }
        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }

    func openPullRequest(remote: String, branch: String) async {
        let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        guard let url = PullRequestURLBuilder.build(remoteURL: remoteURL, branch: branch) else {
            await MainActor.run {
                syncState.showError("Remote '\(remote)' is not a recognized pull request host (GitHub, GitLab, or Bitbucket).")
            }
            return
        }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    func browserURL(from remoteURLString: String) -> URL? {
        var cleaned = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("git@") {
            let withoutPrefix = cleaned.dropFirst("git@".count)
            if let colonIndex = withoutPrefix.firstIndex(of: ":") {
                let host = withoutPrefix[..<colonIndex]
                let path = withoutPrefix[withoutPrefix.index(after: colonIndex)...]
                cleaned = "https://\(host)/\(path)"
            }
        }
        if cleaned.hasPrefix("ssh://") {
            cleaned = String(cleaned.dropFirst("ssh://".count))
            if cleaned.hasPrefix("git@") {
                cleaned = String(cleaned.dropFirst("git@".count))
            }
            cleaned = "https://\(cleaned)"
        }
        if cleaned.hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(".git".count))
        }
        return URL(string: cleaned)
    }
}
