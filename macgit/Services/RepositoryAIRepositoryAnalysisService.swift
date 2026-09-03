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

nonisolated protocol RepositoryAIRepositoryAnalysisServicing: Sendable {
    func compareRefs(base: RepositoryAIRef, head: RepositoryAIRef, in repositoryURL: URL, characterBudget: Int) async throws -> RepositoryAIRefComparison
    func currentComparisonFingerprint(base: RepositoryAIRef, head: RepositoryAIRef, in repositoryURL: URL) async throws -> String
    func searchHistory(_ search: RepositoryAIHistorySearch, in repositoryURL: URL, characterBudget: Int) async throws -> RepositoryAIHistorySearchResult
}

extension GitStatusService: RepositoryAIRepositoryAnalysisServicing {
    func compareRefs(
        base: RepositoryAIRef,
        head: RepositoryAIRef,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> RepositoryAIRefComparison {
        let resolvedBase = try await resolveRepositoryAIRef(base, in: repositoryURL)
        let resolvedHead = try await resolveRepositoryAIRef(head, in: repositoryURL)
        let mergeBase: String
        do {
            mergeBase = try await runGit(arguments: ["merge-base", resolvedBase.objectID, resolvedHead.objectID], in: repositoryURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw RepositoryAIError.noRepositoryData("a merge base between \(base.name) and \(head.name)")
        }
        guard Self.isObjectID(mergeBase) else {
            throw RepositoryAIError.noRepositoryData("a merge base between \(base.name) and \(head.name)")
        }

        let safeEnvironment = ProcessInfo.processInfo.environment.merging([
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_PAGER": "cat",
            "PAGER": "cat",
            "GIT_EXTERNAL_DIFF": "",
        ]) { _, safetyValue in safetyValue }

        async let countsOutput = runGit(arguments: ["rev-list", "--left-right", "--count", "\(resolvedBase.objectID)...\(resolvedHead.objectID)"], in: repositoryURL)
        async let commitsOutput = runGit(arguments: ["log", "--format=%H%x1f%s", "-n", "40", "\(resolvedBase.objectID)..\(resolvedHead.objectID)"], in: repositoryURL)
        async let namesOutput = runGitBounded(arguments: ["diff", "--name-status", "--find-renames", "--no-ext-diff", "--no-textconv", mergeBase, resolvedHead.objectID, "--"], in: repositoryURL, environment: safeEnvironment, outputByteLimit: 20_000)
        async let statsOutput = runGitBounded(arguments: ["diff", "--numstat", "--find-renames", "--no-ext-diff", "--no-textconv", mergeBase, resolvedHead.objectID, "--"], in: repositoryURL, environment: safeEnvironment, outputByteLimit: 20_000)
        async let patchOutput = runGitBounded(arguments: ["diff", "--no-color", "--find-renames", "--no-ext-diff", "--no-textconv", "--unified=3", mergeBase, resolvedHead.objectID, "--"], in: repositoryURL, environment: safeEnvironment, outputByteLimit: max(1_000, characterBudget - 2_400))

        let counts = try await countsOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t")
            .compactMap { Int($0) }
        guard counts.count == 2 else { throw RepositoryAIError.invalidResponse("Git returned invalid ahead/behind counts.") }
        let names = try await namesOutput
        let stats = try await statsOutput
        let boundedPatch = try await patchOutput
        return RepositoryAIRefComparison(
            base: resolvedBase,
            head: resolvedHead,
            mergeBaseObjectID: mergeBase,
            commitsBehind: counts[0],
            commitsAhead: counts[1],
            headOnlyCommits: try await commitsOutput.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, Self.isObjectID(String(parts[0])) else { return nil }
                return RepositoryAIComparedCommit(objectID: String(parts[0]), subject: String(parts[1]))
            },
            nameStatus: names.text,
            numberStats: stats.text,
            patch: boundedPatch.text,
            isTruncated: names.isTruncated || stats.isTruncated || boundedPatch.isTruncated
        )
    }

    func currentComparisonFingerprint(
        base: RepositoryAIRef,
        head: RepositoryAIRef,
        in repositoryURL: URL
    ) async throws -> String {
        let comparison = try await compareRefs(base: base, head: head, in: repositoryURL, characterBudget: 1_000)
        return comparison.fingerprint
    }

    func searchHistory(
        _ search: RepositoryAIHistorySearch,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> RepositoryAIHistorySearchResult {
        var arguments = ["log", "--format=%H%x1f%aI%x1f%an%x1f%s%x1f%b%x1e", "-n", "\(search.limit + 1)", "--regexp-ignore-case", "--grep=\(search.query)"]
        if let author = search.author { arguments.append("--author=\(author)") }
        if let since = search.since { arguments.append("--since=\(Self.iso8601.string(from: since))") }
        if let until = search.until { arguments.append("--until=\(Self.iso8601.string(from: until))") }
        if search.order == .oldestFirst { arguments.append("--reverse") }
        switch search.scope {
        case .currentBranch: arguments.append("HEAD")
        case .localBranches: arguments.append("--branches")
        case .allReferences: arguments.append("--all")
        }
        if let path = search.path { arguments.append(contentsOf: ["--", path]) }
        let output = try await runGit(arguments: arguments, in: repositoryURL)
        let rawRecords = output.split(separator: "\u{1E}", omittingEmptySubsequences: true)
        var commits: [RepositoryAIHistoryCommit] = []
        for record in rawRecords.prefix(search.limit) {
            let fields = record.split(separator: "\u{1F}", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5, Self.isObjectID(String(fields[0])) else { continue }
            let objectID = String(fields[0])
            let pathsOutput = try await runGitBounded(
                arguments: ["show", "--format=", "--name-only", "--no-renames", objectID, "--"],
                in: repositoryURL,
                environment: ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0", "GIT_PAGER": "cat", "PAGER": "cat"]) { _, safetyValue in safetyValue },
                outputByteLimit: 20_000
            )
            let paths = pathsOutput.text.split(separator: "\n").prefix(8).map(String.init)
            let snippetBudget = max(80, characterBudget / max(1, search.limit) - 180)
            commits.append(RepositoryAIHistoryCommit(
                objectID: objectID,
                date: Self.iso8601.date(from: String(fields[1])),
                author: String(fields[2]),
                subject: String(fields[3]),
                snippet: String(fields[4].trimmingCharacters(in: .whitespacesAndNewlines).prefix(snippetBudget)),
                paths: paths
            ))
        }
        let fingerprint = commits.map(\.objectID).joined(separator: ":")
        return RepositoryAIHistorySearchResult(search: search, commits: commits, isTruncated: rawRecords.count > search.limit, fingerprint: fingerprint)
    }

    private func resolveRepositoryAIRef(_ ref: RepositoryAIRef, in repositoryURL: URL) async throws -> RepositoryAICommitReference {
        do {
            let output = try await runGit(arguments: ["rev-parse", "--verify", "\(ref.name)^{commit}"], in: repositoryURL)
            let objectID = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.isObjectID(objectID) else { throw RepositoryAIError.invalidCommitReference }
            return RepositoryAICommitReference(requestedRef: ref, objectID: objectID)
        } catch {
            throw RepositoryAIError.invalidCommitReference
        }
    }

    private static let iso8601 = ISO8601DateFormatter()

    private static func isObjectID(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-fA-F]{40,64}$"#, options: .regularExpression) != nil
    }
}
