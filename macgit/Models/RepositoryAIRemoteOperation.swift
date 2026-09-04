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

nonisolated enum RepositoryAIRemoteOperation: Equatable, Sendable {
    case fetch(remoteID: String)
    case pullFastForward(remoteID: String, branchID: String)
    case pushCurrentBranch(remoteID: String)

    var actionName: String {
        switch self {
        case .fetch: "fetch_remote"
        case .pullFastForward: "pull_fast_forward"
        case .pushCurrentBranch: "push_current_branch"
        }
    }
}

nonisolated struct RepositoryAIRemoteManifest: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let identityFingerprint: String
    let trackingRefsFingerprint: String
}

nonisolated struct RepositoryAIRemoteBranchManifest: Identifiable, Equatable, Sendable {
    let id: String
    let localBranch: String
    let remoteID: String
    let remoteBranch: String
    let upstreamRef: String
    let localObjectID: String
    let remoteTrackingObjectID: String?
    let commitsAhead: Int
    let commitsBehind: Int
    let isProtected: Bool
}

nonisolated struct RepositoryAIRemoteOperationPlanningContext: Equatable, Sendable {
    let repositoryIdentity: String
    let repositoryState: RepositoryAIRepositoryState
    let remotes: [RepositoryAIRemoteManifest]
    let currentBranch: RepositoryAIRemoteBranchManifest?
    let inProgressOperation: String?
    let isWorkingTreeClean: Bool

    func remote(id: String) -> RepositoryAIRemoteManifest? {
        remotes.first { $0.id == id }
    }

    func branch(id: String) -> RepositoryAIRemoteBranchManifest? {
        guard currentBranch?.id == id else { return nil }
        return currentBranch
    }
}

nonisolated enum RepositoryAIRemotePreflightRequirement: String, Equatable, Sendable {
    case remoteIdentityUnchanged
    case localHeadUnchanged
    case upstreamUnchanged
    case remoteTrackingRefUnchanged
    case indexUnchanged
    case workingTreeUnchanged
    case noInProgressOperation
    case cleanWorkingTree
    case fastForwardOnly
    case ordinaryPushOnly
}

nonisolated struct RepositoryAIRemoteExpectedState: Equatable, Sendable {
    let repositoryIdentity: String
    let repositoryState: RepositoryAIRepositoryState
    let remote: RepositoryAIRemoteManifest
    let branch: RepositoryAIRemoteBranchManifest?
}

nonisolated struct RepositoryAIRemoteOperationPreview: Equatable, Sendable {
    let title: String
    let confirmationLabel: String
    let summary: String
    let warning: String?
    let items: [RepositoryAIMutationPreviewItem]
    let details: [RepositoryAIMutationPreviewItem]
}

nonisolated struct RepositoryAIValidatedRemoteOperation: Equatable, Sendable {
    let operation: RepositoryAIRemoteOperation
    let preview: RepositoryAIRemoteOperationPreview
    let expectedState: RepositoryAIRemoteExpectedState
    let requirements: [RepositoryAIRemotePreflightRequirement]
}

nonisolated struct PendingRepositoryAIRemoteOperation: Identifiable, Equatable, Sendable {
    let id: UUID
    let validatedOperation: RepositoryAIValidatedRemoteOperation
    let conversationID: String
    let originatingMessageID: UUID
    let providerID: AIProviderID
    let createdAt: Date
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        validatedOperation: RepositoryAIValidatedRemoteOperation,
        conversationID: String,
        originatingMessageID: UUID,
        providerID: AIProviderID,
        createdAt: Date = .now,
        lifetime: TimeInterval = 300
    ) {
        self.id = id
        self.validatedOperation = validatedOperation
        self.conversationID = conversationID
        self.originatingMessageID = originatingMessageID
        self.providerID = providerID
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(lifetime)
    }

    var operation: RepositoryAIRemoteOperation { validatedOperation.operation }
    var preview: RepositoryAIRemoteOperationPreview { validatedOperation.preview }
    var expectedState: RepositoryAIRemoteExpectedState { validatedOperation.expectedState }
}

nonisolated struct RepositoryAIRemoteOperationExecutionResult: Equatable, Sendable {
    let summary: String
}

nonisolated enum RepositoryAIRemoteOperationError: LocalizedError, Equatable, Sendable {
    case invalidProviderResponse(String)
    case rejected(String)
    case stale(String)
    case cancelled(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidProviderResponse(let reason):
            "Repository AI returned an invalid remote-operation proposal: \(reason)"
        case .rejected(let reason):
            "Repository AI remote operation rejected: \(reason)"
        case .stale(let reason):
            "Repository AI remote operation is stale: \(reason)"
        case .cancelled(let reason):
            "Repository AI remote operation was cancelled: \(reason)"
        case .unavailable:
            "Repository AI remote-operation execution is unavailable in this repository window."
        }
    }
}
