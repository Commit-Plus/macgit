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

nonisolated struct RepositoryAICommitChoice: Identifiable, Equatable, Sendable {
    let hash: String
    let subject: String

    var id: String { hash }
}

nonisolated enum RepositoryAIToolCall: Equatable, Sendable {
    case workingTreeChanges
    case commitChanges(reference: String)

    var name: String {
        switch self {
        case .workingTreeChanges: "working_tree_changes"
        case .commitChanges: "commit_changes"
        }
    }
}

nonisolated struct RepositoryAIToolResult: Equatable, Sendable {
    let toolName: String
    let title: String
    let fingerprint: String
    let content: String
    let isTruncated: Bool
}

nonisolated struct RepositoryAIRequest: Sendable {
    let repositoryName: String
    let branchName: String?
    let question: String
    let toolResult: RepositoryAIToolResult
    let sessionID: String?

    init(
        repositoryName: String,
        branchName: String?,
        question: String,
        toolResult: RepositoryAIToolResult,
        sessionID: String? = nil
    ) {
        self.repositoryName = repositoryName
        self.branchName = branchName
        self.question = question
        self.toolResult = toolResult
        self.sessionID = sessionID
    }

    /// Only file contexts expose opaque evidence IDs that can be cited and
    /// subsequently validated. Other Repository AI contexts accept normal
    /// Markdown responses, even if a provider chooses JSON-like prose.
    var requiresStructuredResponse: Bool {
        switch toolResult.toolName {
        case "read_file_context", "read_file_diff": true
        default: false
        }
    }
}

nonisolated enum RepositoryAIMessageRole: Sendable {
    case user
    case assistant
    case toolActivity
}

nonisolated struct RepositoryAIMessage: Identifiable, Sendable {
    let id: UUID
    let role: RepositoryAIMessageRole
    let text: String
    let contextTitle: String?
    let toolResult: RepositoryAIAgentToolResult?
    let citations: [RepositoryAICitation]
    let evidenceManifest: RepositoryAIEvidenceManifest?

    init(
        id: UUID = UUID(),
        role: RepositoryAIMessageRole,
        text: String,
        contextTitle: String? = nil,
        toolResult: RepositoryAIAgentToolResult? = nil,
        citations: [RepositoryAICitation] = [],
        evidenceManifest: RepositoryAIEvidenceManifest? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.contextTitle = contextTitle
        self.toolResult = toolResult
        self.citations = citations
        self.evidenceManifest = evidenceManifest
    }
}

nonisolated enum RepositoryAIError: LocalizedError, Equatable {
    case emptyQuestion
    case invalidCommitReference
    case invalidRefReference
    case noRepositoryData(String)
    case contextChanged
    case emptyResponse
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuestion:
            "Ask a question about the selected repository context."
        case .invalidCommitReference:
            "Enter a valid commit hash, branch, tag, or HEAD."
        case .invalidRefReference:
            "Enter a valid local, remote-tracking, tag, or HEAD ref."
        case .noRepositoryData(let context):
            "No \(context) are available to analyze."
        case .contextChanged:
            "The repository context changed while AI was responding. Ask again to use the latest changes."
        case .emptyResponse:
            "The AI provider returned an empty response."
        case .invalidResponse(let message):
            message
        }
    }
}
