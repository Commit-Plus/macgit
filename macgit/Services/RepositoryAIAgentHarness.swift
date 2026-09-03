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

actor RepositoryAIAgentHarness {
    private let commandExecutor: any RepositoryAIGitCommandExecuting
    private let stateProvider: any RepositoryAIRepositoryStateProviding
    private let maximumToolCalls: Int
    private let commandTimeout: Duration
    private let requestTimeout: Duration

    init() {
        self.init(
            commandExecutor: RepositoryAIGitCommandExecutor(),
            stateProvider: RepositoryAIRepositoryStateProvider()
        )
    }

    init(
        commandExecutor: any RepositoryAIGitCommandExecuting,
        stateProvider: any RepositoryAIRepositoryStateProviding,
        maximumToolCalls: Int = 6,
        commandTimeout: Duration = .seconds(20),
        requestTimeout: Duration = .seconds(90)
    ) {
        self.commandExecutor = commandExecutor
        self.stateProvider = stateProvider
        self.maximumToolCalls = maximumToolCalls
        self.commandTimeout = commandTimeout
        self.requestTimeout = requestTimeout
    }

    func answer(
        question: String,
        repositoryURL: URL,
        branchName: String?,
        conversation: [RepositoryAIMessage] = [],
        provider: any CommitMessageAIProvider
    ) async throws -> RepositoryAIAgentRunResult {
        try await withThrowingTaskGroup(of: RepositoryAIAgentRunResult.self) { group in
            group.addTask {
                try await self.answerWithinDeadline(
                    question: question,
                    repositoryURL: repositoryURL,
                    branchName: branchName,
                    conversation: conversation,
                    provider: provider
                )
            }
            group.addTask {
                try await Task.sleep(for: self.requestTimeout)
                throw RepositoryAIAgentError.requestTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw RepositoryAIAgentError.requestTimedOut
            }
            return result
        }
    }

    private func answerWithinDeadline(
        question: String,
        repositoryURL: URL,
        branchName: String?,
        conversation: [RepositoryAIMessage],
        provider: any CommitMessageAIProvider
    ) async throws -> RepositoryAIAgentRunResult {
        let initialState = try await stateProvider.state(in: repositoryURL)
        var results = [RepositoryAIAgentToolResult]()
        var isFirstTurn = true

        while true {
            try Task.checkCancellation()
            let turn = try await provider.generateRepositoryAgentTurn(
                request: RepositoryAIAgentRequest(
                    repositoryName: repositoryURL.lastPathComponent,
                    branchName: branchName,
                    question: question,
                    conversation: conversation,
                    previousToolResults: results,
                    isFirstTurn: isFirstTurn
                )
            )
            isFirstTurn = false

            if turn.toolCalls.isEmpty {
                let answer = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !answer.isEmpty else { throw RepositoryAIAgentError.emptyResponse }
                guard results.contains(where: { $0.commandResult.succeeded }) else {
                    throw RepositoryAIAgentError.noRepositoryEvidence
                }
                let finalState = try await stateProvider.state(in: repositoryURL)
                guard initialState == finalState else {
                    throw RepositoryAIAgentError.repositoryChanged
                }
                return RepositoryAIAgentRunResult(answer: answer, toolResults: results)
            }

            guard results.count + turn.toolCalls.count <= maximumToolCalls else {
                throw RepositoryAIAgentError.tooManyToolCalls
            }

            for toolCall in turn.toolCalls {
                guard toolCall.name == "execute_git" else {
                    throw RepositoryAIAgentError.unsupportedTool(toolCall.name)
                }
                let result = try await executeWithTimeout(
                    toolCall.arguments,
                    repositoryURL: repositoryURL,
                    outputCharacterLimit: max(
                        800,
                        (provider.descriptor.inputCharacterBudget - 3_000) / maximumToolCalls
                    )
                )
                results.append(RepositoryAIAgentToolResult(
                    toolCall: toolCall,
                    commandResult: result
                ))
            }
        }
    }

    private func executeWithTimeout(
        _ arguments: [String],
        repositoryURL: URL,
        outputCharacterLimit: Int
    ) async throws -> RepositoryAIGitCommandResult {
        try await withThrowingTaskGroup(of: RepositoryAIGitCommandResult.self) { group in
            group.addTask {
                try await self.commandExecutor.execute(
                    arguments: arguments,
                    in: repositoryURL,
                    outputCharacterLimit: outputCharacterLimit
                )
            }
            group.addTask {
                try await Task.sleep(for: self.commandTimeout)
                throw RepositoryAIAgentError.commandTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw RepositoryAIAgentError.commandTimedOut
            }
            return result
        }
    }
}
