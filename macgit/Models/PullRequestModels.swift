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

enum PullRequestState: String, Codable, Equatable {
    case open
    case closed
    case merged
    case draft
}

enum PullRequestListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case closed = "Closed"

    var id: String { rawValue }

    func includes(_ state: PullRequestState) -> Bool {
        switch self {
        case .all:
            return true
        case .open:
            return state == .open || state == .draft
        case .closed:
            return state == .closed || state == .merged
        }
    }
}

enum PullRequestCheckState: String, Codable, Equatable {
    case unknown
    case noChecks
    case pending
    case success
    case failure
    case error
}

enum PullRequestMergeReadiness: String, Codable, Equatable {
    case unknown
    case ready
    case blocked
}

struct PullRequestAuthor: Equatable, Codable {
    var username: String
    var avatarURL: URL?
}

struct PullRequestBranchRef: Equatable, Codable {
    var label: String
    var ref: String
    var sha: String?
}

struct PullRequestSummary: Identifiable, Equatable, Codable {
    var id: Int { number }
    var number: Int
    var title: String
    var state: PullRequestState
    var author: PullRequestAuthor
    var source: PullRequestBranchRef
    var target: PullRequestBranchRef
    var webURL: URL
    var createdAt: Date
    var updatedAt: Date
    var mergedAt: Date?
    var checkState: PullRequestCheckState
    var mergeReadiness: PullRequestMergeReadiness

    init(
        number: Int,
        title: String,
        state: PullRequestState,
        author: PullRequestAuthor,
        source: PullRequestBranchRef,
        target: PullRequestBranchRef,
        webURL: URL,
        createdAt: Date? = nil,
        updatedAt: Date,
        mergedAt: Date? = nil,
        checkState: PullRequestCheckState = .unknown,
        mergeReadiness: PullRequestMergeReadiness = .unknown
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.author = author
        self.source = source
        self.target = target
        self.webURL = webURL
        self.createdAt = createdAt ?? updatedAt
        self.updatedAt = updatedAt
        self.mergedAt = mergedAt
        self.checkState = checkState
        self.mergeReadiness = mergeReadiness
    }
}

struct PullRequestComment: Identifiable, Equatable, Codable {
    var id: Int
    var author: PullRequestAuthor
    var body: String
    var webURL: URL
    var createdAt: Date
    var updatedAt: Date
}

struct PullRequestDetail: Identifiable, Equatable, Codable {
    var id: Int { summary.id }
    var summary: PullRequestSummary
    var body: String
    var assignees: [PullRequestAuthor]
    var comments: [PullRequestComment]
    var changesURL: URL
}

enum PullRequestDraftValidationError: LocalizedError, Equatable {
    case sameSourceAndTargetBranch

    var errorDescription: String? {
        switch self {
        case .sameSourceAndTargetBranch:
            "Source and target branches must be different."
        }
    }
}

struct PullRequestDraft: Equatable {
    var repository: GitRepositoryIdentity
    var sourceBranch: String
    var targetBranch: String
    var title: String
    var body: String

    init(
        repository: GitRepositoryIdentity,
        sourceBranch: String,
        targetBranch: String,
        title: String,
        body: String
    ) throws {
        let normalizedSource = sourceBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSource != normalizedTarget else {
            throw PullRequestDraftValidationError.sameSourceAndTargetBranch
        }

        self.repository = repository
        self.sourceBranch = normalizedSource
        self.targetBranch = normalizedTarget
        self.title = title
        self.body = body
    }
}

extension GitRepositoryIdentity {
    var browserURL: URL? {
        switch provider {
        case .github, .gitlab:
            hostURL
                .appendingPathComponent(owner)
                .appendingPathComponent(name)
        }
    }
}
