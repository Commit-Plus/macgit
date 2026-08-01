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

protocol CommitChangeSnapshotLoading: Sendable {
    func stagedCommitChangeSnapshot(
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot

    func stagedChangesFingerprint(in repositoryURL: URL) async throws -> String
}

extension GitStatusService: CommitChangeSnapshotLoading {
    func stagedCommitChangeSnapshot(
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        let nameStatus = try await runGit(
            arguments: ["diff", "--cached", "--name-status", "--no-renames"],
            in: repositoryURL
        )
        guard !nameStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommitMessageGenerationError.noStagedChanges
        }

        let numberStats = try await runGit(
            arguments: ["diff", "--cached", "--numstat", "--no-renames"],
            in: repositoryURL
        )
        let patch = try await runGit(
            arguments: [
                "diff", "--cached", "--no-color", "--no-ext-diff", "--no-textconv",
                "--unified=3", "--no-renames",
            ],
            in: repositoryURL
        )
        let fingerprint = try await stagedChangesFingerprint(in: repositoryURL)
        let built = CommitMessageContextBuilder.build(
            nameStatus: nameStatus,
            numberStats: numberStats,
            patch: patch,
            characterBudget: characterBudget
        )
        return CommitChangeSnapshot(
            fingerprint: fingerprint,
            context: built.context,
            isTruncated: built.isTruncated
        )
    }

    func stagedChangesFingerprint(in repositoryURL: URL) async throws -> String {
        try await runGit(arguments: ["write-tree"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
