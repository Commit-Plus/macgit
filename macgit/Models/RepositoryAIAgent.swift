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

nonisolated struct RepositoryAIAgentToolCall: Equatable, Sendable {
    let id: String
    let name: String
    let arguments: [String]
}

nonisolated struct RepositoryAIAgentTurn: Equatable, Sendable {
    let text: String
    let toolCalls: [RepositoryAIAgentToolCall]
}

nonisolated struct RepositoryAIAgentToolResult: Equatable, Sendable {
    let toolCall: RepositoryAIAgentToolCall
    let commandResult: RepositoryAIGitCommandResult
}

nonisolated struct RepositoryAIAgentRequest: Sendable {
    let repositoryName: String
    let branchName: String?
    let question: String
    let conversation: [RepositoryAIMessage]
    let previousToolResults: [RepositoryAIAgentToolResult]
    let isFirstTurn: Bool
}

nonisolated struct RepositoryAIAgentRunResult: Equatable, Sendable {
    let answer: String
    let toolResults: [RepositoryAIAgentToolResult]
}

nonisolated enum RepositoryAIAgentError: LocalizedError, Equatable {
    case unsupportedTool(String)
    case noRepositoryEvidence
    case tooManyToolCalls
    case emptyResponse
    case unsupportedProvider(String)
    case commandTimedOut
    case requestTimedOut
    case repositoryChanged

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let tool):
            "Repository AI requested an unsupported tool: \(tool)."
        case .noRepositoryEvidence:
            "Repository AI must read repository evidence before answering."
        case .tooManyToolCalls:
            "Repository AI reached its Git query limit. Ask a narrower question."
        case .emptyResponse:
            "The AI provider returned an empty Repository AI response."
        case .unsupportedProvider(let provider):
            "\(provider) does not yet support Repository AI Git tools. Choose a tool-capable provider and try again."
        case .commandTimedOut:
            "A Git query took too long and was stopped. Ask a narrower question."
        case .requestTimedOut:
            "Repository AI took too long to answer. Ask a narrower question and try again."
        case .repositoryChanged:
            "The repository changed while AI was analyzing it. Ask again to use the latest state."
        }
    }
}
