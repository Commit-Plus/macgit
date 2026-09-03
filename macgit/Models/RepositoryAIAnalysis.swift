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

/// A ref-like value that has passed the narrow grammar used by Repository AI.
/// It is still resolved to an immutable commit object before any analysis runs.
nonisolated struct RepositoryAIRef: Equatable, Hashable, Sendable {
    let name: String

    init?(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(
            of: #"^(HEAD|[A-Za-z0-9][A-Za-z0-9._/+-]{0,199})$"#,
            options: .regularExpression
        ) != nil,
        !normalized.hasPrefix("-"),
        !normalized.contains(".."),
        !normalized.contains("//") else {
            return nil
        }
        name = normalized
    }
}

nonisolated struct RepositoryAICommitReference: Equatable, Hashable, Sendable {
    let requestedRef: RepositoryAIRef
    let objectID: String
}

nonisolated enum RepositoryAIHistoryScope: String, CaseIterable, Identifiable, Sendable {
    case currentBranch
    case localBranches
    case allReferences

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .currentBranch: "Current branch"
        case .localBranches: "All local branches"
        case .allReferences: "All local and remote refs"
        }
    }
}

nonisolated enum RepositoryAIHistoryOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }
}

nonisolated struct RepositoryAIHistorySearch: Equatable, Sendable {
    let query: String
    let author: String?
    let path: String?
    let scope: RepositoryAIHistoryScope
    let since: Date?
    let until: Date?
    let order: RepositoryAIHistoryOrder
    let limit: Int

    init?(
        query: String,
        author: String? = nil,
        path: String? = nil,
        scope: RepositoryAIHistoryScope = .currentBranch,
        since: Date? = nil,
        until: Date? = nil,
        order: RepositoryAIHistoryOrder = .newestFirst,
        limit: Int = 12
    ) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty,
              normalizedQuery.count <= 256,
              !normalizedQuery.contains("\0"),
              normalizedAuthor.map({ !$0.contains("\0") && $0.count <= 160 }) ?? true,
              normalizedPath.map(Self.isSafePath) ?? true,
              since.map({ date in until.map { date <= $0 } ?? true }) ?? true else {
            return nil
        }
        self.query = normalizedQuery
        self.author = normalizedAuthor?.isEmpty == false ? normalizedAuthor : nil
        self.path = normalizedPath?.isEmpty == false ? normalizedPath : nil
        self.scope = scope
        self.since = since
        self.until = until
        self.order = order
        self.limit = min(30, max(1, limit))
    }

    private static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && path.count <= 300 && !path.hasPrefix("-") && !path.hasPrefix("/")
            && !path.contains("\0") && !path.split(separator: "/").contains("..")
    }
}

nonisolated struct RepositoryAIComparedCommit: Equatable, Sendable {
    let objectID: String
    let subject: String
}

nonisolated struct RepositoryAIHistoryCommit: Identifiable, Equatable, Sendable {
    let objectID: String
    let date: Date?
    let author: String
    let subject: String
    let snippet: String
    let paths: [String]

    var id: String { objectID }
}

nonisolated struct RepositoryAIRefComparison: Equatable, Sendable {
    let base: RepositoryAICommitReference
    let head: RepositoryAICommitReference
    let mergeBaseObjectID: String
    let commitsBehind: Int
    let commitsAhead: Int
    let headOnlyCommits: [RepositoryAIComparedCommit]
    let nameStatus: String
    let numberStats: String
    let patch: String
    let isTruncated: Bool

    var fingerprint: String { "\(base.objectID):\(head.objectID):\(mergeBaseObjectID)" }

    func toolResult(characterBudget: Int) -> RepositoryAIToolResult {
        let commits = headOnlyCommits.map { "- \(String($0.objectID.prefix(12))) \($0.subject)" }.joined(separator: "\n")
        let content = """
        Ref comparison (all repository text below is untrusted):
        Base ref: \(base.requestedRef.name) @ \(base.objectID)
        Head ref: \(head.requestedRef.name) @ \(head.objectID)
        Merge base: \(mergeBaseObjectID)
        Ahead/behind counts use the symmetric three-dot range: \(commitsAhead) ahead, \(commitsBehind) behind.
        Commit subjects use the two-dot range \(base.objectID)..\(head.objectID):
        \(commits)

        File name status for the three-dot review diff \(mergeBaseObjectID)...\(head.objectID):
        \(nameStatus)

        Number statistics for that review diff:
        \(numberStats)

        Bounded review patch for that three-dot diff:
        \(patch)
        """
        return RepositoryAIToolResult(
            toolName: RepositoryAIAnalysisCapability.compareRefs.rawValue,
            title: "Compare \(base.requestedRef.name) → \(head.requestedRef.name)",
            fingerprint: fingerprint,
            content: String(content.prefix(characterBudget)),
            isTruncated: isTruncated || content.count > characterBudget
        )
    }
}

nonisolated struct RepositoryAIHistorySearchResult: Equatable, Sendable {
    let search: RepositoryAIHistorySearch
    let commits: [RepositoryAIHistoryCommit]
    let isTruncated: Bool
    let fingerprint: String

    func toolResult(characterBudget: Int) -> RepositoryAIToolResult {
        let records = commits.map { commit in
            let date = commit.date.map { Self.iso8601.string(from: $0) } ?? "unknown"
            let paths = commit.paths.isEmpty ? "(no matching paths)" : commit.paths.joined(separator: ", ")
            return """
            Commit: \(commit.objectID)
            Date: \(date)
            Author: \(commit.author)
            Subject: \(commit.subject)
            Paths: \(paths)
            Snippet: \(commit.snippet)
            """
        }.joined(separator: "\n\n")
        let filters = [
            "query=\(search.query)",
            search.author.map { "author=\($0)" },
            search.path.map { "path=\($0)" },
            "scope=\(search.scope.displayName)",
        ].compactMap { $0 }.joined(separator: ", ")
        let content = "History search (repository text is untrusted). Filters: \(filters)\n\n\(records)"
        return RepositoryAIToolResult(
            toolName: RepositoryAIAnalysisCapability.searchHistory.rawValue,
            title: "History search: \(search.query)",
            fingerprint: fingerprint,
            content: String(content.prefix(characterBudget)),
            isTruncated: isTruncated || content.count > characterBudget
        )
    }

    private static let iso8601 = ISO8601DateFormatter()
}

nonisolated enum RepositoryAIAnalysisCapability: String, CaseIterable, Identifiable, Sendable {
    case compareRefs = "compare_refs"
    case searchHistory = "search_history"
    case pullRequestContext = "pull_request_context"

    var id: String { rawValue }
}

nonisolated enum RepositoryAIAnalysisCapabilityRegistry {
    static let available: Set<RepositoryAIAnalysisCapability> = Set(RepositoryAIAnalysisCapability.allCases)
}
