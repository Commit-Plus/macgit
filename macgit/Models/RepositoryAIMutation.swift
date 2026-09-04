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

nonisolated enum RepositoryAIMutationPathSource: String, Equatable, Sendable {
    case staged
    case unstaged
    case untracked
    case conflict
}

nonisolated struct RepositoryAIMutationPath: Identifiable, Equatable, Sendable {
    let id: String
    let file: StatusFile
    let source: RepositoryAIMutationPathSource

    var displayStatus: String {
        switch source {
        case .staged: "Staged \(file.status.rawValue)"
        case .unstaged: "Unstaged \(file.status.rawValue)"
        case .untracked: "Untracked"
        case .conflict: "Unresolved conflict"
        }
    }
}

nonisolated struct RepositoryAIMutationRef: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let commit: String
}

nonisolated struct RepositoryAIMutationStatistics: Equatable, Sendable {
    let fileCount: Int
    let additions: Int
    let deletions: Int
    let binaryFileCount: Int
}

nonisolated struct RepositoryAIConflictResolutionManifest: Identifiable, Equatable, Sendable {
    struct FileResolution: Equatable, Sendable {
        let loadedFile: ConflictAILoadedFile
        let resolvedDocument: ConflictResolutionDocument
    }

    let id: String
    let repositoryIdentity: String
    let providerID: AIProviderID
    let files: [FileResolution]
    let createdAt: Date
}

nonisolated enum RepositoryAIMutationProposal: Equatable, Sendable {
    case stageFiles(paths: [RepositoryAIMutationPath])
    case unstageFiles(paths: [RepositoryAIMutationPath])
    case createCommit(message: String)
    case createBranch(name: String, startPoint: RepositoryAIMutationRef)
    case checkoutBranch(target: RepositoryAIMutationRef)
    case applyConflictResolution(RepositoryAIConflictResolutionManifest)

    var actionName: String {
        switch self {
        case .stageFiles: "stage_files"
        case .unstageFiles: "unstage_files"
        case .createCommit: "create_commit"
        case .createBranch: "create_branch"
        case .checkoutBranch: "checkout_branch"
        case .applyConflictResolution: "apply_conflict_resolution"
        }
    }
}

nonisolated enum RepositoryAIMutationProviderResponse: Equatable, Sendable {
    case proposal(RepositoryAIMutationProposal)
    case unsupported(reason: String)
}

nonisolated enum RepositoryAIMutationActionState: Equatable, Sendable {
    case stage
    case unstage
    case commit(author: String, signingEnabled: Bool)
    case createBranch(name: String, startPoint: RepositoryAIMutationRef)
    case checkoutBranch(previousRef: String, target: RepositoryAIMutationRef)
    case conflictResolution(id: String, fingerprints: [String: String])
}

nonisolated struct RepositoryAIMutationPrecondition: Equatable, Sendable {
    let repositoryIdentity: String
    let repositoryState: RepositoryAIRepositoryState
    let selectedPaths: [RepositoryAIMutationPath]
    let actionState: RepositoryAIMutationActionState
}

nonisolated struct RepositoryAIMutationPreviewItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
}

nonisolated struct RepositoryAIMutationPreview: Equatable, Sendable {
    let title: String
    let confirmationLabel: String
    let summary: String
    let warning: String?
    let items: [RepositoryAIMutationPreviewItem]
    let details: [RepositoryAIMutationPreviewItem]
}

nonisolated struct RepositoryAIValidatedMutation: Equatable, Sendable {
    let proposal: RepositoryAIMutationProposal
    let preview: RepositoryAIMutationPreview
    let precondition: RepositoryAIMutationPrecondition
}

nonisolated struct PendingRepositoryAIMutation: Identifiable, Equatable, Sendable {
    let id: UUID
    let validatedMutation: RepositoryAIValidatedMutation
    let conversationID: String
    let originatingMessageID: UUID
    let providerID: AIProviderID
    let createdAt: Date
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        validatedMutation: RepositoryAIValidatedMutation,
        conversationID: String,
        originatingMessageID: UUID,
        providerID: AIProviderID,
        createdAt: Date = .now,
        lifetime: TimeInterval = 300
    ) {
        self.id = id
        self.validatedMutation = validatedMutation
        self.conversationID = conversationID
        self.originatingMessageID = originatingMessageID
        self.providerID = providerID
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(lifetime)
    }

    var proposal: RepositoryAIMutationProposal { validatedMutation.proposal }
    var preview: RepositoryAIMutationPreview { validatedMutation.preview }
    var precondition: RepositoryAIMutationPrecondition { validatedMutation.precondition }
}

nonisolated struct RepositoryAIMutationExecutionResult: Equatable, Sendable {
    let summary: String
}

nonisolated enum RepositoryAIMutationError: LocalizedError, Equatable, Sendable {
    case invalidProviderResponse(String)
    case rejected(String)
    case stale(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidProviderResponse(let reason):
            "Repository AI returned an invalid mutation proposal: \(reason)"
        case .rejected(let reason):
            "Repository AI mutation rejected: \(reason)"
        case .stale(let reason):
            "Repository AI proposal is stale: \(reason)"
        case .unavailable:
            "Repository AI mutation execution is unavailable in this repository window."
        }
    }
}
