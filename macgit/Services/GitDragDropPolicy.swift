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
            guard isCurrent else {
                return .reject("Drop commits only on the current branch.")
            }
            guard commits.allSatisfy({ !$0.isMerge }) else {
                return .reject("Merge commits are not supported by drag and drop yet.")
            }
            return .accept(.cherryPick(commits: commits, targetBranch: name))

        case .branchesHeader:
            guard commits.count == 1, let commit = commits.first else {
                return .reject("Select one commit to create a branch.")
            }
            return .accept(.createBranch(startPoint: .commit(hash: commit.hash, message: commit.message)))

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

        case .stashesHeader, .fileStatus:
            return .reject("That drag and drop action is not available yet.")
        }
    }
}
