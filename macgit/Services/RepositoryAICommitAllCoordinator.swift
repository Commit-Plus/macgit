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
protocol RepositoryAICommitAllPreparing {
    func prepare(in repositoryURL: URL) async throws -> RepositoryAICommitAllPreparationResult
}

@MainActor
final class RepositoryAICommitAllCoordinator: RepositoryAICommitAllPreparing {
    private let providerController: AIProviderController
    private let gitService: GitStatusService
    private let contextProvider: any RepositoryAIMutationContextProviding
    private let mutationExecutor: any RepositoryAIMutationExecuting

    init(
        providerController: AIProviderController,
        gitService: GitStatusService = .shared,
        contextProvider: any RepositoryAIMutationContextProviding,
        mutationExecutor: any RepositoryAIMutationExecuting
    ) {
        self.providerController = providerController
        self.gitService = gitService
        self.contextProvider = contextProvider
        self.mutationExecutor = mutationExecutor
    }

    func prepare(in repositoryURL: URL) async throws -> RepositoryAICommitAllPreparationResult {
        let initialContext = try await contextProvider.context(in: repositoryURL)
        let stageMutation = try RepositoryAIMutationPolicy.validateCommitAllPreparation(
            context: initialContext
        )
        let stageResult = try await mutationExecutor.execute(stageMutation, in: repositoryURL)

        do {
            try Task.checkCancellation()
            let branch = await gitService.currentBranch(in: repositoryURL)
            let recentCommits = await gitService.recentCommits(limit: 8, in: repositoryURL)
            let generatedMessage = try await providerController.generateCommitMessage(
                repositoryURL: repositoryURL,
                branchName: branch,
                changeSource: .staged,
                recentCommitSubjects: recentCommits.map(\.message)
            )
            try Task.checkCancellation()

            let commitContext = try await contextProvider.context(in: repositoryURL)
            let validatedCommit = try RepositoryAIMutationPolicy.validate(
                .createCommit(message: generatedMessage.text),
                context: commitContext
            )
            let stagedCount = stageMutation.precondition.selectedPaths.count
            let basePreview = validatedCommit.preview
            let preview = RepositoryAIMutationPreview(
                title: basePreview.title,
                confirmationLabel: basePreview.confirmationLabel,
                summary: "All current changes were staged automatically. Create one commit with this generated message:",
                warning: "Staging already completed and has its own Git Undo entry. Cancelling leaves the changes staged. Hooks and configured commit signing may run when you confirm.",
                items: basePreview.items,
                details: [
                    RepositoryAIMutationPreviewItem(
                        id: "auto-staged-count",
                        title: "Automatically staged",
                        detail: stagedCount == 1 ? "1 changed file" : "\(stagedCount) changed files"
                    ),
                ] + basePreview.details
            )
            return RepositoryAICommitAllPreparationResult(
                stageSummary: stageResult.summary,
                commitMutation: RepositoryAIValidatedMutation(
                    proposal: validatedCommit.proposal,
                    preview: preview,
                    precondition: validatedCommit.precondition
                )
            )
        } catch is CancellationError {
            throw RepositoryAICommitAllPreparationError.cancelledAfterStaging
        } catch {
            throw RepositoryAICommitAllPreparationError.stagedButCouldNotPrepareCommit(
                error.localizedDescription
            )
        }
    }
}

nonisolated enum RepositoryAICommitAllPreparationError: LocalizedError, Equatable, Sendable {
    case cancelledAfterStaging
    case stagedButCouldNotPrepareCommit(String)

    var errorDescription: String? {
        switch self {
        case .cancelledAfterStaging:
            "The workflow was cancelled after staging. The changes remain staged and can be undone with Git Undo."
        case .stagedButCouldNotPrepareCommit(let reason):
            "Changes were staged, but the commit confirmation could not be prepared: \(reason) The changes remain staged and can be undone with Git Undo."
        }
    }
}
