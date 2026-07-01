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

enum GitDragDropPolicy {
    nonisolated static func decision(
        for payload: GitDragPayload,
        target: GitDragTarget,
        receivingRepositoryURL: URL,
        optionKeyPressed: Bool
    ) -> GitDragDropDecision {
        let receivingPath = GitDragPayload.normalizedPath(receivingRepositoryURL)
        guard payload.repositoryPath == receivingPath else {
            return .reject("This drag item came from a different repository.")
        }

        switch payload.content {
        case .commits(let commits):
            return commitDecision(commits: commits, target: target)
        case .branch(let source):
            return branchDecision(source: source, target: target, optionKeyPressed: optionKeyPressed)
        case .remoteBranch(let source):
            return remoteBranchDecision(source: source, target: target)
        case .files, .stash:
            return .reject("That drag and drop action is not available yet.")
        }
    }

    nonisolated private static func commitDecision(
        commits: [GitDraggedCommit],
        target: GitDragTarget
    ) -> GitDragDropDecision {
        guard !commits.isEmpty else {
            return .reject("Select at least one commit to drag.")
        }

        switch target {
        case .localBranch(let name, let isCurrent):
            guard commits.allSatisfy({ !$0.isMerge }) else {
                return .reject("Merge commits are not supported by drag and drop yet.")
            }
            guard isCurrent else {
                return .reject("Drop commits only on the current HEAD branch.")
            }
            return .accept(.cherryPick(commits: commits, targetBranch: name))

        case .branchesHeader:
            guard commits.count == 1, let commit = commits.first else {
                return .reject("Select one commit to create a branch.")
            }
            return .accept(.createBranch(startPoint: .commit(hash: commit.hash, message: commit.message)))

        case .tagsHeader:
            return .reject("Drop a branch onto Tags to create a tag.")

        case .remotesHeader:
            return .reject("Drop a branch onto Remotes to push it.")

        case .stashesHeader, .fileStatus:
            return .reject("That drag and drop action is not available yet.")
        }
    }

    nonisolated private static func branchDecision(
        source: String,
        target: GitDragTarget,
        optionKeyPressed: Bool
    ) -> GitDragDropDecision {
        switch target {
        case .localBranch(let name, let isCurrent):
            guard isCurrent else {
                return .reject("Drop branches only on the current branch.")
            }
            guard source != name else {
                return .reject("Drop a different branch onto the current branch.")
            }
            return .accept(
                .branchOperation(
                    source: source,
                    target: name,
                    operation: optionKeyPressed ? .rebase : .merge
                )
            )

        case .branchesHeader:
            return .accept(.createBranch(startPoint: .branch(source)))

        case .tagsHeader:
            return .accept(.createTagFromBranch(source))

        case .remotesHeader:
            return .accept(.pushBranchToRemote(source))

        case .stashesHeader, .fileStatus:
            return .reject("That drag and drop action is not available yet.")
        }
    }

    nonisolated private static func remoteBranchDecision(
        source: String,
        target: GitDragTarget
    ) -> GitDragDropDecision {
        guard target == .branchesHeader else {
            return .reject("Drop remote branches onto Branches to check them out.")
        }

        return .accept(.checkoutRemoteBranch(source))
    }
}
