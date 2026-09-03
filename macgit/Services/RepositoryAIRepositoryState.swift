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

import CryptoKit
import Foundation

nonisolated struct RepositoryAIRepositoryState: Equatable, Sendable {
    let branch: String?
    let head: String
    let stagedFingerprint: String
    let workingTreeFingerprint: String
}

nonisolated protocol RepositoryAIRepositoryStateProviding: Sendable {
    func state(in repositoryURL: URL) async throws -> RepositoryAIRepositoryState
}

actor RepositoryAIRepositoryStateProvider: RepositoryAIRepositoryStateProviding {
    private let gitService: GitStatusService

    init(gitService: GitStatusService = .shared) {
        self.gitService = gitService
    }

    func state(in repositoryURL: URL) async throws -> RepositoryAIRepositoryState {
        let head = (try? await gitService.runGit(
            arguments: ["rev-parse", "--verify", "HEAD"],
            in: repositoryURL
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "<unborn>"
        let safeEnvironment = ProcessInfo.processInfo.environment.merging([
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_PAGER": "cat",
            "PAGER": "cat",
            "GIT_EXTERNAL_DIFF": "",
        ]) { _, safetyValue in safetyValue }
        let stagedPatch = try await gitService.runGitBounded(
            arguments: [
                "--no-pager", "-c", "color.ui=false", "-c", "core.pager=cat",
                "diff", "--cached", "--binary", "--no-ext-diff", "--no-textconv", "--no-color",
            ],
            in: repositoryURL,
            environment: safeEnvironment,
            outputByteLimit: 512_000
        )
        guard !stagedPatch.isTruncated else {
            throw RepositoryAIAgentError.repositoryChanged
        }
        let stagedFingerprint = fingerprint(stagedPatch.text)
        let workingTreeFingerprint = try await gitService.changesFingerprint(
            in: repositoryURL,
            source: .workingTree
        )
        return RepositoryAIRepositoryState(
            branch: await gitService.currentBranch(in: repositoryURL),
            head: head,
            stagedFingerprint: stagedFingerprint,
            workingTreeFingerprint: workingTreeFingerprint
        )
    }

    private func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
