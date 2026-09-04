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
protocol RepositoryAIMutationExecuting {
    func execute(
        _ mutation: RepositoryAIValidatedMutation,
        in repositoryURL: URL
    ) async throws -> RepositoryAIMutationExecutionResult
}

@MainActor
final class RepositoryAIMutationExecutor: RepositoryAIMutationExecuting {
    private let gitService: GitStatusService
    private let contextProvider: any RepositoryAIMutationContextProviding
    private let conflictFileService: any ConflictAIFileServicing
    private let conflictRegistry: RepositoryAIConflictResolutionRegistry
    private let undoManager: GitUndoManager
    private let syncState: SyncState
    private let operationProgress: RepositoryOperationProgress

    init(
        gitService: GitStatusService = .shared,
        contextProvider: any RepositoryAIMutationContextProviding = RepositoryAIMutationContextProvider(),
        conflictFileService: any ConflictAIFileServicing = GitStatusService.shared,
        conflictRegistry: RepositoryAIConflictResolutionRegistry = .shared,
        undoManager: GitUndoManager,
        syncState: SyncState,
        operationProgress: RepositoryOperationProgress
    ) {
        self.gitService = gitService
        self.contextProvider = contextProvider
        self.conflictFileService = conflictFileService
        self.conflictRegistry = conflictRegistry
        self.undoManager = undoManager
        self.syncState = syncState
        self.operationProgress = operationProgress
    }

    func execute(
        _ mutation: RepositoryAIValidatedMutation,
        in repositoryURL: URL
    ) async throws -> RepositoryAIMutationExecutionResult {
        guard operationProgress.activeOperation == nil, !syncState.isAnySyncing else {
            throw RepositoryAIMutationError.stale("Another repository operation is active.")
        }

        let currentContext = try await contextProvider.context(in: repositoryURL)
        guard RepositoryAIMutationPolicy.isCurrent(
            mutation.precondition,
            proposal: mutation.proposal,
            context: currentContext
        ) else {
            throw RepositoryAIMutationError.stale("HEAD, index, working tree, selected paths, or refs changed. Review a new proposal.")
        }
        _ = try RepositoryAIMutationPolicy.validate(mutation.proposal, context: currentContext)

        let progressID = operationProgress.begin(
            message: "Repository AI: \(mutation.preview.title)…",
            canCancel: false
        )
        var didAttemptMutation = false
        defer { operationProgress.end(progressID) }

        do {
            let result: RepositoryAIMutationExecutionResult
            didAttemptMutation = true
            switch mutation.proposal {
            case .stageFiles(let paths):
                try await gitService.stageAll(files: paths.map(\.file), in: repositoryURL)
                undoManager.register(GitUndoEntryFactory.stageFiles(
                    repositoryURL: repositoryURL,
                    paths: paths.map(\.file.path)
                ))
                result = RepositoryAIMutationExecutionResult(
                    summary: paths.count == 1
                        ? "Succeeded — staged \(paths[0].file.path)."
                        : "Succeeded — staged \(paths.count) files."
                )
            case .unstageFiles(let paths):
                try await gitService.unstageAll(files: paths.map(\.file), in: repositoryURL)
                undoManager.register(GitUndoEntryFactory.unstageFiles(
                    repositoryURL: repositoryURL,
                    paths: paths.map(\.file.path)
                ))
                result = RepositoryAIMutationExecutionResult(
                    summary: paths.count == 1
                        ? "Succeeded — unstaged \(paths[0].file.path)."
                        : "Succeeded — unstaged \(paths.count) files."
                )
            case .createCommit(let message):
                let oldHead = mutation.precondition.repositoryState.head
                try await gitService.commit(message: message, in: repositoryURL)
                guard let newHead = await gitService.tipHash(for: "HEAD", in: repositoryURL),
                      newHead != oldHead else {
                    throw RepositoryAIMutationError.stale("Git did not create the expected new commit.")
                }
                undoManager.register(GitUndoEntryFactory.commit(
                    repositoryURL: repositoryURL,
                    oldHead: oldHead,
                    newHead: newHead,
                    message: message,
                    noVerify: false,
                    signOff: false
                ))
                result = RepositoryAIMutationExecutionResult(
                    summary: "Succeeded — created commit \(newHead.prefix(12))."
                )
            case .createBranch(let name, let startPoint):
                _ = try await gitService.createBranch(
                    name: name,
                    checkout: false,
                    commit: startPoint.commit,
                    in: repositoryURL
                )
                undoManager.register(GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: "Create branch \(name)",
                    undoOperation: .deleteLocalBranch(name: name, force: true, expectedTip: startPoint.commit),
                    redoOperation: .createLocalBranch(name: name, startPoint: startPoint.commit, checkout: false)
                ))
                result = RepositoryAIMutationExecutionResult(
                    summary: "Succeeded — created local branch \(name) at \(startPoint.commit.prefix(12))."
                )
            case .checkoutBranch(let target):
                guard case .checkoutBranch(let previousRef, _) = mutation.precondition.actionState else {
                    throw RepositoryAIMutationError.stale("The checkout precondition is invalid.")
                }
                try await gitService.checkoutCommit(target.name, in: repositoryURL)
                undoManager.register(GitUndoEntry(
                    repositoryURL: repositoryURL,
                    label: "Checkout \(target.name)",
                    undoOperation: .checkoutRef(ref: previousRef),
                    redoOperation: .checkoutRef(ref: target.name)
                ))
                result = RepositoryAIMutationExecutionResult(
                    summary: "Succeeded — checked out local branch \(target.name)."
                )
            case .applyConflictResolution(let manifest):
                for fileResolution in manifest.files {
                    try await conflictFileService.applyAIConflictResolution(
                        file: fileResolution.loadedFile.file,
                        document: fileResolution.resolvedDocument,
                        expectedFingerprint: fileResolution.loadedFile.snapshot.fingerprint,
                        originalWorkingTreeText: fileResolution.loadedFile.originalWorkingTreeText,
                        in: repositoryURL
                    )
                }
                await conflictRegistry.remove(
                    id: manifest.id,
                    repositoryIdentity: manifest.repositoryIdentity
                )
                result = RepositoryAIMutationExecutionResult(
                    summary: manifest.files.count == 1
                        ? "Succeeded — applied and staged the Conflict AI resolution for \(manifest.files[0].loadedFile.file.path)."
                        : "Succeeded — applied and staged \(manifest.files.count) Conflict AI resolutions."
                )
            }

            await refreshAndNotify(repositoryURL)
            return result
        } catch {
            if didAttemptMutation {
                await refreshAndNotify(repositoryURL)
            }
            throw error
        }
    }

    private func refreshAndNotify(_ repositoryURL: URL) async {
        await syncState.refresh(repositoryURL: repositoryURL)
        NotificationCenter.default.post(
            name: .repositoryDidChange,
            object: nil,
            userInfo: ["repositoryURL": repositoryURL]
        )
    }
}
