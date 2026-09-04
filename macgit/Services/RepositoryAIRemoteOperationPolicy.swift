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

nonisolated enum RepositoryAIRemoteOperationProposalDecoder {
    static let unsupportedToolName = "unsupported_remote_operation"
    static let toolNames: Set<String> = [
        "fetch_remote",
        "pull_fast_forward",
        "push_current_branch",
        unsupportedToolName,
    ]

    static func decode(_ toolCall: RepositoryAIAgentToolCall) throws -> RepositoryAIRemoteOperation? {
        switch toolCall.name {
        case "fetch_remote":
            guard toolCall.arguments.count == 1 else {
                throw RepositoryAIRemoteOperationError.invalidProviderResponse("Fetch requires exactly one supplied remote ID.")
            }
            return .fetch(remoteID: toolCall.arguments[0])
        case "pull_fast_forward":
            guard toolCall.arguments.count == 2 else {
                throw RepositoryAIRemoteOperationError.invalidProviderResponse("Pull requires exactly one supplied remote ID and branch ID.")
            }
            return .pullFastForward(remoteID: toolCall.arguments[0], branchID: toolCall.arguments[1])
        case "push_current_branch":
            guard toolCall.arguments.count == 1 else {
                throw RepositoryAIRemoteOperationError.invalidProviderResponse("Push requires exactly one supplied remote ID.")
            }
            return .pushCurrentBranch(remoteID: toolCall.arguments[0])
        case unsupportedToolName:
            guard toolCall.arguments.count == 1,
                  let reason = toolCall.arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !reason.isEmpty,
                  reason.count <= 1_000 else {
                throw RepositoryAIRemoteOperationError.invalidProviderResponse("An unsupported operation requires one concise reason.")
            }
            throw RepositoryAIRemoteOperationError.rejected(reason)
        default:
            throw RepositoryAIRemoteOperationError.invalidProviderResponse("The requested tool is not a supported remote operation.")
        }
    }
}

nonisolated enum RepositoryAIRemoteOperationPolicy {
    static func validate(
        _ operation: RepositoryAIRemoteOperation,
        context: RepositoryAIRemoteOperationPlanningContext
    ) throws -> RepositoryAIValidatedRemoteOperation {
        guard context.inProgressOperation == nil else {
            throw RepositoryAIRemoteOperationError.rejected(
                "Finish the current Git operation before using a Repository AI remote operation."
            )
        }

        switch operation {
        case .fetch(let remoteID):
            let remote = try trustedRemote(id: remoteID, context: context)
            return validated(
                operation,
                remote: remote,
                branch: context.currentBranch,
                context: context,
                requirements: baseRequirements + [.remoteTrackingRefUnchanged, .noInProgressOperation],
                preview: RepositoryAIRemoteOperationPreview(
                    title: "Fetch remote",
                    confirmationLabel: "Fetch \(remote.name)",
                    summary: "Contact this configured remote and update its remote-tracking refs.",
                    warning: "This uses the network. Authentication may be requested, and remote-tracking refs can move.",
                    items: [detail("Remote", remote.name)],
                    details: [
                        detail("Options", "No prune, force, tags, refspec, or URL changes"),
                        detail("Local files", "HEAD, the index, and the working tree are not intentionally changed"),
                    ]
                )
            )
        case .pullFastForward(let remoteID, let branchID):
            let remote = try trustedRemote(id: remoteID, context: context)
            let branch = try trustedCurrentBranch(id: branchID, remote: remote, context: context)
            guard context.isWorkingTreeClean else {
                throw RepositoryAIRemoteOperationError.rejected("Commit or stash all working-copy changes before pulling.")
            }
            guard branch.remoteTrackingObjectID != nil else {
                throw RepositoryAIRemoteOperationError.rejected("Fetch the configured upstream before preparing a pull.")
            }
            guard branch.commitsAhead == 0 else {
                let reason = branch.commitsBehind > 0
                    ? "The current branch has diverged from its upstream."
                    : "The current branch is already ahead of its upstream and cannot be fast-forwarded."
                throw RepositoryAIRemoteOperationError.rejected(reason)
            }
            guard branch.commitsBehind > 0 else {
                throw RepositoryAIRemoteOperationError.rejected("The current branch is already up to date.")
            }
            return validated(
                operation,
                remote: remote,
                branch: branch,
                context: context,
                requirements: baseRequirements + [
                    .upstreamUnchanged,
                    .remoteTrackingRefUnchanged,
                    .noInProgressOperation,
                    .cleanWorkingTree,
                    .fastForwardOnly,
                ],
                preview: RepositoryAIRemoteOperationPreview(
                    title: "Fast-forward pull",
                    confirmationLabel: "Pull \(remote.name)/\(branch.remoteBranch)",
                    summary: "Fetch the configured upstream, then fast-forward the current branch only if it remains safe.",
                    warning: "The working tree must remain clean. A changed or diverged upstream cancels the local update.",
                    items: [detail("Target", "\(remote.name)/\(branch.remoteBranch)")],
                    details: objectDetails(branch: branch, countTitle: "Commits to pull", count: branch.commitsBehind)
                )
            )
        case .pushCurrentBranch(let remoteID):
            let remote = try trustedRemote(id: remoteID, context: context)
            let branch = try trustedCurrentBranch(remote: remote, context: context)
            guard branch.remoteTrackingObjectID != nil else {
                throw RepositoryAIRemoteOperationError.rejected(
                    "The configured upstream has no local remote-tracking snapshot. Fetch it before preparing a push."
                )
            }
            guard branch.commitsBehind == 0 else {
                let reason = branch.commitsAhead > 0
                    ? "The current branch has diverged from its upstream."
                    : "The upstream contains commits that are not in the current branch."
                throw RepositoryAIRemoteOperationError.rejected(reason)
            }
            guard branch.commitsAhead > 0 else {
                throw RepositoryAIRemoteOperationError.rejected("The current branch has no commits to push.")
            }
            let warning = branch.isProtected
                ? "\(remote.name)/\(branch.remoteBranch) is the remote's default branch. Review protected-branch rules before pushing."
                : "Git will reject the push if the remote branch changed or the update is not a fast-forward."
            return validated(
                operation,
                remote: remote,
                branch: branch,
                context: context,
                requirements: baseRequirements + [
                    .upstreamUnchanged,
                    .remoteTrackingRefUnchanged,
                    .noInProgressOperation,
                    .ordinaryPushOnly,
                ],
                preview: RepositoryAIRemoteOperationPreview(
                    title: "Push current branch",
                    confirmationLabel: "Push \(branch.localBranch)",
                    summary: "Push the current branch to its configured upstream without force or a model-supplied refspec.",
                    warning: warning,
                    items: [detail("Target", "\(remote.name)/\(branch.remoteBranch)")],
                    details: objectDetails(branch: branch, countTitle: "Commits to push", count: branch.commitsAhead)
                )
            )
        }
    }

    static func isCurrent(
        _ validated: RepositoryAIValidatedRemoteOperation,
        context: RepositoryAIRemoteOperationPlanningContext
    ) -> Bool {
        guard let revalidated = try? validate(validated.operation, context: context) else { return false }
        return revalidated.expectedState == validated.expectedState
            && revalidated.requirements == validated.requirements
    }

    private static let baseRequirements: [RepositoryAIRemotePreflightRequirement] = [
        .remoteIdentityUnchanged,
        .localHeadUnchanged,
        .indexUnchanged,
        .workingTreeUnchanged,
    ]

    private static func trustedRemote(
        id: String,
        context: RepositoryAIRemoteOperationPlanningContext
    ) throws -> RepositoryAIRemoteManifest {
        guard let remote = context.remote(id: id) else {
            throw RepositoryAIRemoteOperationError.rejected("The selected remote is not in the current trusted manifest.")
        }
        return remote
    }

    private static func trustedCurrentBranch(
        id: String? = nil,
        remote: RepositoryAIRemoteManifest,
        context: RepositoryAIRemoteOperationPlanningContext
    ) throws -> RepositoryAIRemoteBranchManifest {
        guard context.repositoryState.branch != nil,
              let branch = context.currentBranch else {
            throw RepositoryAIRemoteOperationError.rejected("The current branch is detached or has no configured upstream.")
        }
        if let id, branch.id != id {
            throw RepositoryAIRemoteOperationError.rejected("The selected branch is not in the current trusted manifest.")
        }
        guard branch.remoteID == remote.id else {
            throw RepositoryAIRemoteOperationError.rejected("The selected remote is not the current branch's configured upstream.")
        }
        return branch
    }

    private static func validated(
        _ operation: RepositoryAIRemoteOperation,
        remote: RepositoryAIRemoteManifest,
        branch: RepositoryAIRemoteBranchManifest?,
        context: RepositoryAIRemoteOperationPlanningContext,
        requirements: [RepositoryAIRemotePreflightRequirement],
        preview: RepositoryAIRemoteOperationPreview
    ) -> RepositoryAIValidatedRemoteOperation {
        RepositoryAIValidatedRemoteOperation(
            operation: operation,
            preview: preview,
            expectedState: RepositoryAIRemoteExpectedState(
                repositoryIdentity: context.repositoryIdentity,
                repositoryState: context.repositoryState,
                remote: remote,
                branch: branch
            ),
            requirements: requirements
        )
    }

    private static func objectDetails(
        branch: RepositoryAIRemoteBranchManifest,
        countTitle: String,
        count: Int
    ) -> [RepositoryAIMutationPreviewItem] {
        [
            detail("Local object", String(branch.localObjectID.prefix(12))),
            detail("Remote object", branch.remoteTrackingObjectID.map { String($0.prefix(12)) } ?? "Not available"),
            detail(countTitle, "\(count)"),
            detail("Upstream", branch.upstreamRef),
        ]
    }

    private static func detail(_ title: String, _ value: String) -> RepositoryAIMutationPreviewItem {
        RepositoryAIMutationPreviewItem(id: "\(title)-\(value)", title: title, detail: value)
    }
}
