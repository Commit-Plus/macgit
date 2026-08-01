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

struct CommitChangeSnapshot: Equatable, Sendable {
    let fingerprint: String
    let context: String
    let isTruncated: Bool
}

struct CommitMessageGenerationRequest: Sendable {
    let repositoryName: String
    let branchName: String?
    let stagedChanges: CommitChangeSnapshot
    let recentCommitSubjects: [String]
}

struct GeneratedCommitMessage: Equatable, Sendable {
    let subject: String
    let body: String?

    var text: String {
        guard let body, !body.isEmpty else { return subject }
        return "\(subject)\n\n\(body)"
    }
}

enum CommitMessageGenerationError: LocalizedError, Equatable {
    case noStagedChanges
    case providerUnavailable(String)
    case providerNotImplemented
    case contextTooLarge
    case invalidResponse
    case stagedChangesChanged

    var errorDescription: String? {
        switch self {
        case .noStagedChanges:
            "Stage changes before generating a commit message."
        case .providerUnavailable(let reason):
            reason
        case .providerNotImplemented:
            "This AI provider is not available yet."
        case .contextTooLarge:
            "The staged changes are too large for Apple Intelligence. Try staging a smaller commit."
        case .invalidResponse:
            "The AI provider did not return a valid commit message."
        case .stagedChangesChanged:
            "Staged changes changed while the message was being generated. Generate it again."
        }
    }
}

