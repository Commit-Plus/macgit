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

import Foundation

@MainActor
protocol RepositoryAIRemoteOperationExecuting {
    func execute(
        _ operation: RepositoryAIValidatedRemoteOperation,
        in repositoryURL: URL
    ) async throws -> RepositoryAIRemoteOperationExecutionResult
}

@MainActor
final class RepositoryAIRemoteOperationExecutor: RepositoryAIRemoteOperationExecuting {
    typealias CredentialResolverProvider = ([String]) async -> GitProviderCredentialResolver?

    private let gitService: GitStatusService
    private let contextProvider: any RepositoryAIRemoteOperationContextProviding
    private let credentialResolverProvider: CredentialResolverProvider
    private let undoManager: GitUndoManager
    private let syncState: SyncState
    private let operationProgress: RepositoryOperationProgress

    init(
        gitService: GitStatusService = .shared,
        contextProvider: any RepositoryAIRemoteOperationContextProviding = RepositoryAIRemoteOperationContextProvider(),
        credentialResolverProvider: @escaping CredentialResolverProvider,
        undoManager: GitUndoManager,
        syncState: SyncState,
        operationProgress: RepositoryOperationProgress
    ) {
        self.gitService = gitService
        self.contextProvider = contextProvider
        self.credentialResolverProvider = credentialResolverProvider
        self.undoManager = undoManager
        self.syncState = syncState
        self.operationProgress = operationProgress
    }

    func execute(
        _ operation: RepositoryAIValidatedRemoteOperation,
        in repositoryURL: URL
    ) async throws -> RepositoryAIRemoteOperationExecutionResult {
        try await validateCurrent(operation, in: repositoryURL)

        let remote = operation.expectedState.remote
        guard let credentialResolver = await credentialResolverProvider([remote.name]) else {
            throw RepositoryAIRemoteOperationError.cancelled("No provider account was selected.")
        }
        // Account selection can keep the task suspended while repository or
        // remote state changes, so the execution boundary gets a fresh check.
        try await validateCurrent(operation, in: repositoryURL)

        let progressID = operationProgress.begin(
            message: "Repository AI: \(operation.preview.title)…",
            canCancel: false
        )
        var didAttemptOperation = false
        defer { operationProgress.end(progressID) }

        do {
            didAttemptOperation = true
            let result: RepositoryAIRemoteOperationExecutionResult
            switch operation.operation {
            case .fetch:
                try await gitService.fetch(
                    remote: remote.name,
                    in: repositoryURL,
                    credentialResolver: credentialResolver
                )
                result = RepositoryAIRemoteOperationExecutionResult(
                    summary: "Succeeded — fetched \(remote.name) and refreshed its remote-tracking refs."
                )
            case .pullFastForward:
                let branch = try requiredBranch(operation)
                let oldHead = branch.localObjectID
                _ = try await gitService.fetchAndFastForwardBranchFromUpstream(
                    branch: branch.localBranch,
                    in: repositoryURL,
                    credentialResolver: credentialResolver
                )
                guard let newHead = await gitService.tipHash(for: "HEAD", in: repositoryURL),
                      newHead != oldHead else {
                    throw RepositoryAIRemoteOperationError.stale(
                        "The upstream no longer contained a new fast-forward update."
                    )
                }
                undoManager.register(GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: "Pull",
                    undoOperation: .resetHead(target: oldHead, mode: .hard, expectedHead: newHead),
                    redoOperation: .resetHead(target: newHead, mode: .hard, expectedHead: oldHead),
                    confirmationMessage: "Undoing a pull will reset the current branch back to its previous commit. Continue?"
                ))
                result = RepositoryAIRemoteOperationExecutionResult(
                    summary: "Succeeded — fast-forwarded \(branch.localBranch) by \(branch.commitsBehind) \(commitLabel(branch.commitsBehind))."
                )
            case .pushCurrentBranch:
                let branch = try requiredBranch(operation)
                _ = try await gitService.push(
                    options: GitStatusService.PushOptions(
                        remote: remote.name,
                        branches: [branch.localBranch],
                        branchMappings: [branch.localBranch: branch.remoteBranch]
                    ),
                    in: repositoryURL,
                    credentialResolver: credentialResolver
                )
                result = RepositoryAIRemoteOperationExecutionResult(
                    summary: "Succeeded — pushed \(branch.commitsAhead) \(commitLabel(branch.commitsAhead)) from \(branch.localBranch) to \(remote.name)/\(branch.remoteBranch)."
                )
            }

            await refreshAndNotify(repositoryURL, updatesRemoteRefs: true)
            return result
        } catch {
            if didAttemptOperation {
                await refreshAndNotify(repositoryURL, updatesRemoteRefs: true)
                syncState.showError(error.localizedDescription)
            }
            throw error
        }
    }

    private func requiredBranch(
        _ operation: RepositoryAIValidatedRemoteOperation
    ) throws -> RepositoryAIRemoteBranchManifest {
        guard let branch = operation.expectedState.branch else {
            throw RepositoryAIRemoteOperationError.stale("The configured upstream branch is no longer available.")
        }
        return branch
    }

    private func validateCurrent(
        _ operation: RepositoryAIValidatedRemoteOperation,
        in repositoryURL: URL
    ) async throws {
        guard operationProgress.activeOperation == nil, !syncState.isAnySyncing else {
            throw RepositoryAIRemoteOperationError.stale("Another repository operation is active.")
        }

        let currentContext = try await contextProvider.context(in: repositoryURL)
        guard RepositoryAIRemoteOperationPolicy.isCurrent(operation, context: currentContext) else {
            throw RepositoryAIRemoteOperationError.stale(
                "The remote, HEAD, upstream, remote-tracking ref, index, or working tree changed. Review a new proposal."
            )
        }
        _ = try RepositoryAIRemoteOperationPolicy.validate(operation.operation, context: currentContext)
    }

    private func commitLabel(_ count: Int) -> String {
        count == 1 ? "commit" : "commits"
    }

    private func refreshAndNotify(_ repositoryURL: URL, updatesRemoteRefs: Bool) async {
        await syncState.refresh(repositoryURL: repositoryURL)
        if updatesRemoteRefs {
            NotificationCenter.default.post(
                name: .repositoryRemoteRefsDidRefresh,
                object: nil,
                userInfo: ["repositoryURL": repositoryURL]
            )
        }
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }
}
