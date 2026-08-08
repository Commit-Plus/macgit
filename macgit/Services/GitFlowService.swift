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

enum GitFlowStartError: LocalizedError, Equatable {
    case dirtyWorkingTree
    case unfinishedOperation
    case missingBaseBranch(String)
    case branchAlreadyExists(String)
    case invalidBranchName(String)

    var errorDescription: String? {
        switch self {
        case .dirtyWorkingTree:
            return "Commit, stash, or discard the current changes before starting Git Flow."
        case .unfinishedOperation:
            return "Finish or abort the current Git operation before starting Git Flow."
        case .missingBaseBranch(let branch):
            return "The starting branch '\(branch)' does not exist."
        case .branchAlreadyExists(let branch):
            return "The branch '\(branch)' already exists."
        case .invalidBranchName(let branch):
            return "'\(branch)' is not a valid Git branch name."
        }
    }
}

enum GitFlowFinishError: LocalizedError, Equatable {
    case dirtyWorkingTree
    case unfinishedOperation
    case currentBranchChanged(expected: String)
    case missingTargetBranch(String)
    case targetCheckedOutInWorktree(String)
    case tagAlreadyExists(String)
    case missingCheckpoint

    var errorDescription: String? {
        switch self {
        case .dirtyWorkingTree:
            return "Commit, stash, or discard the current changes before finishing Git Flow."
        case .unfinishedOperation:
            return "Finish or abort the current Git operation before finishing Git Flow."
        case .currentBranchChanged(let expected):
            return "Check out '\(expected)' again before finishing it."
        case .missingTargetBranch(let branch):
            return "The target branch '\(branch)' does not exist."
        case .targetCheckedOutInWorktree(let branch):
            return "The target branch '\(branch)' is checked out in another worktree."
        case .tagAlreadyExists(let tag):
            return "The tag '\(tag)' already exists."
        case .missingCheckpoint:
            return "There is no Git Flow finish operation to resume."
        }
    }
}

enum GitFlowDevelopBranchCreationError: LocalizedError, Equatable {
    case emptyBranchName
    case missingMainBranch(String)
    case branchAlreadyExists(String)
    case invalidBranchName(String)

    var errorDescription: String? {
        switch self {
        case .emptyBranchName:
            return "Enter a name for the Develop branch."
        case .missingMainBranch(let branch):
            return "The selected Main branch '\(branch)' does not exist."
        case .branchAlreadyExists(let branch):
            return "The branch '\(branch)' already exists. Select it from the Develop branch menu."
        case .invalidBranchName(let branch):
            return "'\(branch)' is not a valid Git branch name."
        }
    }
}

struct GitFlowService {
    private let recoveryStore = GitFlowRecoveryStore()

    func createDevelopBranch(
        name: String,
        startingPoint: String,
        in repositoryURL: URL
    ) async throws -> String {
        let branchName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branchName.isEmpty else {
            throw GitFlowDevelopBranchCreationError.emptyBranchName
        }

        let git = GitStatusService.shared
        let branches = await git.localBranches(in: repositoryURL)
        guard branches.contains(startingPoint) else {
            throw GitFlowDevelopBranchCreationError.missingMainBranch(startingPoint)
        }
        guard !branches.contains(branchName) else {
            throw GitFlowDevelopBranchCreationError.branchAlreadyExists(branchName)
        }
        guard await git.isValidBranchName(branchName, in: repositoryURL) else {
            throw GitFlowDevelopBranchCreationError.invalidBranchName(branchName)
        }

        _ = try await git.createBranch(
            name: branchName,
            checkout: false,
            commit: startingPoint,
            in: repositoryURL
        )
        return branchName
    }

    func start(_ plan: GitFlowStartPlan, in repositoryURL: URL) async throws -> GitFlowStartResult {
        guard await GitStatusService.shared.hasUnfinishedGitFlowStartOperation(in: repositoryURL) == false else {
            throw GitFlowStartError.unfinishedOperation
        }
        guard await GitStatusService.shared.dirtyCount(in: repositoryURL) == 0 else {
            throw GitFlowStartError.dirtyWorkingTree
        }

        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        guard branches.contains(plan.baseBranch) else {
            throw GitFlowStartError.missingBaseBranch(plan.baseBranch)
        }
        guard !branches.contains(plan.branchName) else {
            throw GitFlowStartError.branchAlreadyExists(plan.branchName)
        }
        guard await GitStatusService.shared.isValidBranchName(plan.branchName, in: repositoryURL) else {
            throw GitFlowStartError.invalidBranchName(plan.branchName)
        }

        let support = GitBranchUndoSupport()
        let previousRef = try await support.currentRef(in: repositoryURL)
        let createdTip = try await support.tip(of: plan.baseBranch, in: repositoryURL)
        _ = try await GitStatusService.shared.createBranch(
            name: plan.branchName,
            checkout: true,
            commit: plan.baseBranch,
            in: repositoryURL
        )

        return GitFlowStartResult(
            plan: plan,
            previousRef: previousRef,
            createdTip: createdTip
        )
    }

    func finish(_ plan: GitFlowFinishPlan, in repositoryURL: URL) async throws -> GitFlowFinishResult {
        let git = GitStatusService.shared
        guard await git.hasUnfinishedGitFlowStartOperation(in: repositoryURL) == false else {
            throw GitFlowFinishError.unfinishedOperation
        }
        guard await git.dirtyCount(in: repositoryURL) == 0 else {
            throw GitFlowFinishError.dirtyWorkingTree
        }
        guard await git.currentBranch(in: repositoryURL) == plan.sourceBranch else {
            throw GitFlowFinishError.currentBranchChanged(expected: plan.sourceBranch)
        }
        try await validateTargets(for: plan, in: repositoryURL)
        if plan.createTag, let tagName = plan.tagName, try await tagExists(tagName, in: repositoryURL) {
            throw GitFlowFinishError.tagAlreadyExists(tagName)
        }

        let support = GitBranchUndoSupport()
        let sourceTip = try await support.tip(of: plan.sourceBranch, in: repositoryURL)
        var checkpoint = GitFlowFinishCheckpoint(
            plan: plan,
            sourceTip: sourceTip,
            targetResults: [],
            createdTagName: nil,
            phase: .primaryMerge
        )
        try await recoveryStore.save(checkpoint, in: repositoryURL)

        checkpoint = try await mergeTarget(at: 0, checkpoint: checkpoint, in: repositoryURL)
        checkpoint = try await createTagIfNeeded(checkpoint, in: repositoryURL)
        if plan.secondaryTargetBranch != nil {
            checkpoint.phase = .secondaryMerge
            try await recoveryStore.save(checkpoint, in: repositoryURL)
            checkpoint = try await mergeTarget(at: 1, checkpoint: checkpoint, in: repositoryURL)
        }

        var didDelete = false
        var deletionWarning: String?
        if plan.deleteSourceBranch {
            do {
                _ = try await git.deleteBranch(name: plan.sourceBranch, force: false, in: repositoryURL)
                didDelete = true
            } catch {
                deletionWarning = "The merge completed, but Commit+ could not delete '\(plan.sourceBranch)': \(error.localizedDescription)"
            }
        }
        try await recoveryStore.clear(in: repositoryURL)

        return GitFlowFinishResult(
            plan: plan,
            sourceTip: sourceTip,
            targetResults: checkpoint.targetResults,
            createdTagName: checkpoint.createdTagName,
            didDeleteSourceBranch: didDelete,
            deletionWarning: deletionWarning
        )
    }

    func resumeFinish(in repositoryURL: URL) async throws -> GitFlowFinishResult {
        guard var checkpoint = await recoveryStore.checkpoint(in: repositoryURL) else {
            throw GitFlowFinishError.missingCheckpoint
        }
        let git = GitStatusService.shared
        if await git.isMergeInProgress(in: repositoryURL) {
            _ = try await git.runGit(arguments: ["merge", "--continue"], in: repositoryURL)
        } else if await git.dirtyCount(in: repositoryURL) != 0 {
            throw GitFlowFinishError.dirtyWorkingTree
        }

        switch checkpoint.phase {
        case .primaryMerge:
            checkpoint = try await recordCurrentMergeIfNeeded(at: 0, checkpoint: checkpoint, in: repositoryURL)
            checkpoint = try await createTagIfNeeded(checkpoint, in: repositoryURL)
            if checkpoint.plan.secondaryTargetBranch != nil {
                checkpoint.phase = .secondaryMerge
                try await recoveryStore.save(checkpoint, in: repositoryURL)
                checkpoint = try await mergeTarget(at: 1, checkpoint: checkpoint, in: repositoryURL)
            }
        case .secondaryMerge:
            checkpoint = try await recordCurrentMergeIfNeeded(at: 1, checkpoint: checkpoint, in: repositoryURL)
        }

        var didDelete = false
        var deletionWarning: String?
        if checkpoint.plan.deleteSourceBranch {
            do {
                _ = try await git.deleteBranch(name: checkpoint.plan.sourceBranch, force: false, in: repositoryURL)
                didDelete = true
            } catch {
                deletionWarning = "The merge completed, but Commit+ could not delete '\(checkpoint.plan.sourceBranch)': \(error.localizedDescription)"
            }
        }
        try await recoveryStore.clear(in: repositoryURL)

        return GitFlowFinishResult(
            plan: checkpoint.plan,
            sourceTip: checkpoint.sourceTip,
            targetResults: checkpoint.targetResults,
            createdTagName: checkpoint.createdTagName,
            didDeleteSourceBranch: didDelete,
            deletionWarning: deletionWarning
        )
    }

    func abortFinish(in repositoryURL: URL) async throws {
        guard let checkpoint = await recoveryStore.checkpoint(in: repositoryURL) else {
            throw GitFlowFinishError.missingCheckpoint
        }
        let git = GitStatusService.shared
        if await git.isMergeInProgress(in: repositoryURL) {
            try await git.abortMerge(in: repositoryURL)
        }
        if let tagName = checkpoint.createdTagName {
            try? await git.deleteTag(name: tagName, in: repositoryURL)
        }
        for target in checkpoint.targetResults.reversed() {
            _ = try await git.runGit(arguments: ["checkout", target.branch], in: repositoryURL)
            _ = try await git.runGit(arguments: ["reset", "--hard", target.tipBeforeMerge], in: repositoryURL)
        }
        _ = try await git.runGit(arguments: ["checkout", checkpoint.plan.sourceBranch], in: repositoryURL)
        try await recoveryStore.clear(in: repositoryURL)
    }

    private func mergeMessage(for plan: GitFlowFinishPlan) -> String {
        "Finish \(plan.kind.displayName.lowercased()) '\(plan.sourceBranch)'"
    }

    private func validateTargets(for plan: GitFlowFinishPlan, in repositoryURL: URL) async throws {
        let git = GitStatusService.shared
        let branches = await git.localBranches(in: repositoryURL)
        for branch in plan.targetBranches {
            guard branches.contains(branch) else {
                throw GitFlowFinishError.missingTargetBranch(branch)
            }
            if try await git.worktreePath(for: branch, in: repositoryURL) != nil {
                throw GitFlowFinishError.targetCheckedOutInWorktree(branch)
            }
        }
    }

    private func mergeTarget(
        at index: Int,
        checkpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws -> GitFlowFinishCheckpoint {
        var checkpoint = checkpoint
        let plan = checkpoint.plan
        let branch = plan.targetBranches[index]
        let support = GitBranchUndoSupport()
        let oldTip = try await support.tip(of: branch, in: repositoryURL)
        _ = try await GitStatusService.shared.runGit(arguments: ["checkout", branch], in: repositoryURL)
        checkpoint.phase = index == 0 ? .primaryMerge : .secondaryMerge
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        _ = try await GitStatusService.shared.runGit(
            arguments: ["merge", "--no-ff", plan.sourceBranch, "-m", mergeMessage(for: plan)],
            in: repositoryURL
        )
        let newTip = try await support.tip(of: branch, in: repositoryURL)
        checkpoint.targetResults.append(
            GitFlowFinishTargetResult(branch: branch, tipBeforeMerge: oldTip, tipAfterMerge: newTip)
        )
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        return checkpoint
    }

    private func recordCurrentMergeIfNeeded(
        at index: Int,
        checkpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws -> GitFlowFinishCheckpoint {
        var checkpoint = checkpoint
        guard checkpoint.targetResults.count == index else { return checkpoint }
        let branch = checkpoint.plan.targetBranches[index]
        let support = GitBranchUndoSupport()
        let newTip = try await support.tip(of: branch, in: repositoryURL)
        let beforeTip = try await support.tip(of: "HEAD^1", in: repositoryURL)
        checkpoint.targetResults.append(
            GitFlowFinishTargetResult(branch: branch, tipBeforeMerge: beforeTip, tipAfterMerge: newTip)
        )
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        return checkpoint
    }

    private func createTagIfNeeded(
        _ checkpoint: GitFlowFinishCheckpoint,
        in repositoryURL: URL
    ) async throws -> GitFlowFinishCheckpoint {
        var checkpoint = checkpoint
        guard checkpoint.createdTagName == nil,
              checkpoint.plan.createTag,
              let tagName = checkpoint.plan.tagName,
              let target = checkpoint.targetResults.first else {
            return checkpoint
        }
        if try await tagExists(tagName, in: repositoryURL) {
            throw GitFlowFinishError.tagAlreadyExists(tagName)
        }
        try await GitStatusService.shared.createTag(
            name: tagName,
            commit: target.tipAfterMerge,
            annotated: true,
            message: "Release \(tagName)",
            in: repositoryURL
        )
        checkpoint.createdTagName = tagName
        try await recoveryStore.save(checkpoint, in: repositoryURL)
        return checkpoint
    }

    private func tagExists(_ tag: String, in repositoryURL: URL) async throws -> Bool {
        do {
            _ = try await GitStatusService.shared.runGit(
                arguments: ["show-ref", "--verify", "--quiet", "refs/tags/\(tag)"],
                in: repositoryURL
            )
            return true
        } catch {
            return false
        }
    }
}
