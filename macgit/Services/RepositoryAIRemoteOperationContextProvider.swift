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

import CryptoKit
import Foundation

nonisolated protocol RepositoryAIRemoteOperationContextProviding: Sendable {
    func context(in repositoryURL: URL) async throws -> RepositoryAIRemoteOperationPlanningContext
}

actor RepositoryAIRemoteOperationContextProvider: RepositoryAIRemoteOperationContextProviding {
    private let gitService: GitStatusService
    private let stateProvider: any RepositoryAIRepositoryStateProviding

    init(
        gitService: GitStatusService = .shared,
        stateProvider: any RepositoryAIRepositoryStateProviding = RepositoryAIRepositoryStateProvider()
    ) {
        self.gitService = gitService
        self.stateProvider = stateProvider
    }

    func context(in repositoryURL: URL) async throws -> RepositoryAIRemoteOperationPlanningContext {
        async let loadedState = stateProvider.state(in: repositoryURL)
        async let loadedRemotes = gitService.remotes(in: repositoryURL)
        async let loadedOperation = gitService.inProgressOperation(in: repositoryURL)
        async let loadedUnfinishedOperation = gitService.hasUnfinishedGitFlowStartOperation(in: repositoryURL)
        async let loadedCleanState = GitStashUndoSupport().isWorkingTreeClean(in: repositoryURL)

        let state = try await loadedState
        let remoteNames = await loadedRemotes.sorted()
        let operation = await loadedOperation
        let hasUnfinishedOperation = await loadedUnfinishedOperation
        let repositoryIdentity = RepositoryAIMutationContextProvider.repositoryIdentity(for: repositoryURL)

        var remotes: [RepositoryAIRemoteManifest] = []
        for (index, name) in remoteNames.enumerated() {
            let remoteURL = await gitService.remoteURL(remote: name, in: repositoryURL)
            guard !remoteURL.isEmpty else { continue }
            let trackingRefs = (try? await gitService.runGit(
                arguments: [
                    "for-each-ref",
                    "--format=%(refname)%00%(objectname)",
                    "refs/remotes/\(name)/",
                ],
                in: repositoryURL
            )) ?? ""
            remotes.append(RepositoryAIRemoteManifest(
                id: "remote-\(index + 1)",
                name: name,
                identityFingerprint: Self.fingerprint(remoteURL),
                trackingRefsFingerprint: Self.fingerprint(trackingRefs)
            ))
        }

        let currentBranch = try await currentBranchManifest(
            state: state,
            remotes: remotes,
            repositoryURL: repositoryURL
        )

        return RepositoryAIRemoteOperationPlanningContext(
            repositoryIdentity: repositoryIdentity,
            repositoryState: state,
            remotes: remotes,
            currentBranch: currentBranch,
            inProgressOperation: operation?.displayName ?? (hasUnfinishedOperation ? "Merge or rebase" : nil),
            isWorkingTreeClean: try await loadedCleanState
        )
    }

    private func currentBranchManifest(
        state: RepositoryAIRepositoryState,
        remotes: [RepositoryAIRemoteManifest],
        repositoryURL: URL
    ) async throws -> RepositoryAIRemoteBranchManifest? {
        guard let localBranch = state.branch,
              state.head != "<unborn>",
              let upstreamRef = await gitService.upstreamBranch(for: localBranch, in: repositoryURL),
              let target = Self.resolveUpstream(upstreamRef, remotes: remotes) else {
            return nil
        }

        let remoteTrackingObjectID = await gitService.tipHash(for: upstreamRef, in: repositoryURL)
        let counts = try await aheadBehind(
            localRef: localBranch,
            remoteRef: upstreamRef,
            repositoryURL: repositoryURL
        )
        let defaultBranch = await gitService.defaultBranch(in: repositoryURL, remote: target.remote.name)
        let normalizedDefault = defaultBranch.map {
            $0.hasPrefix("\(target.remote.name)/")
                ? String($0.dropFirst(target.remote.name.count + 1))
                : $0
        }

        return RepositoryAIRemoteBranchManifest(
            id: "current-upstream",
            localBranch: localBranch,
            remoteID: target.remote.id,
            remoteBranch: target.branch,
            upstreamRef: upstreamRef,
            localObjectID: state.head,
            remoteTrackingObjectID: remoteTrackingObjectID,
            commitsAhead: counts.ahead,
            commitsBehind: counts.behind,
            isProtected: normalizedDefault == target.branch
        )
    }

    private func aheadBehind(
        localRef: String,
        remoteRef: String,
        repositoryURL: URL
    ) async throws -> (ahead: Int, behind: Int) {
        let output = try await gitService.runGit(
            arguments: ["rev-list", "--count", "--left-right", "\(remoteRef)...\(localRef)"],
            in: repositoryURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = output.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            throw RepositoryAIRemoteOperationError.rejected("The current upstream comparison could not be resolved.")
        }
        return (ahead, behind)
    }

    nonisolated private static func resolveUpstream(
        _ upstream: String,
        remotes: [RepositoryAIRemoteManifest]
    ) -> (remote: RepositoryAIRemoteManifest, branch: String)? {
        let matchingRemote = remotes
            .sorted { $0.name.count > $1.name.count }
            .first { upstream.hasPrefix("\($0.name)/") }
        guard let matchingRemote else { return nil }
        let branch = String(upstream.dropFirst(matchingRemote.name.count + 1))
        guard !branch.isEmpty else { return nil }
        return (matchingRemote, branch)
    }

    nonisolated private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
