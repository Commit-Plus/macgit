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

struct GitFlowService {
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
}
