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

nonisolated protocol RepositoryAIGitCommandExecuting: Sendable {
    func execute(
        arguments: [String],
        in repositoryURL: URL,
        outputCharacterLimit: Int
    ) async throws -> RepositoryAIGitCommandResult
}

actor RepositoryAIGitCommandExecutor: RepositoryAIGitCommandExecuting {
    private let gitService: GitStatusService

    init(gitService: GitStatusService = .shared) {
        self.gitService = gitService
    }

    func execute(
        arguments: [String],
        in repositoryURL: URL,
        outputCharacterLimit: Int
    ) async throws -> RepositoryAIGitCommandResult {
        let validated = try RepositoryAIGitCommandPolicy.validatedArguments(arguments)
        let limit = max(800, outputCharacterLimit)
        let environment = ProcessInfo.processInfo.environment.merging([
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_PAGER": "cat",
            "PAGER": "cat",
            "GIT_EXTERNAL_DIFF": "",
        ]) { _, safetyValue in safetyValue }
        let displayCommand = "git " + arguments.joined(separator: " ")

        do {
            let output = try await gitService.runGitBounded(
                arguments: validated,
                in: repositoryURL,
                environment: environment,
                outputByteLimit: limit
            )
            return RepositoryAIGitCommandResult(
                displayCommand: displayCommand,
                output: output.text,
                succeeded: true,
                isTruncated: output.isTruncated
            )
        } catch let error as GitError {
            return result(
                displayCommand: displayCommand,
                output: error.localizedDescription,
                succeeded: false,
                limit: limit
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return result(
                displayCommand: displayCommand,
                output: error.localizedDescription,
                succeeded: false,
                limit: limit
            )
        }
    }

    private func result(
        displayCommand: String,
        output: String,
        succeeded: Bool,
        limit: Int
    ) -> RepositoryAIGitCommandResult {
        let bounded = String(output.prefix(limit))
        return RepositoryAIGitCommandResult(
            displayCommand: displayCommand,
            output: bounded,
            succeeded: succeeded,
            isTruncated: bounded.count < output.count
        )
    }
}
