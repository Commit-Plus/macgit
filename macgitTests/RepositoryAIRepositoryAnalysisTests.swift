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
import XCTest
@testable import macgit

final class RepositoryAIRepositoryAnalysisTests: XCTestCase {
    func testComparisonUsesResolvedObjectsAndReviewDiff() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        _ = try runGit(["branch", "feature"], in: repository)
        _ = try runGit(["checkout", "feature"], in: repository)
        _ = try runGit(["mv", "Example.swift", "Renamed.swift"], in: repository)
        try "let value = 2\n".write(to: repository.appending(path: "Renamed.swift"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "-A"], in: repository)
        _ = try runGit(["commit", "-m", "Rename example"], in: repository)

        let base = try XCTUnwrap(RepositoryAIRef("main"))
        let head = try XCTUnwrap(RepositoryAIRef("feature"))
        let service = GitStatusService.shared
        let comparison = try await service.compareRefs(base: base, head: head, in: repository, characterBudget: 8_000)

        XCTAssertEqual(comparison.commitsAhead, 1)
        XCTAssertEqual(comparison.commitsBehind, 0)
        XCTAssertEqual(comparison.headOnlyCommits.first?.subject, "Rename example")
        XCTAssertTrue(comparison.nameStatus.contains("Renamed.swift"))
        let initialFingerprint = comparison.fingerprint
        try "let value = 3\n".write(to: repository.appending(path: "Renamed.swift"), atomically: true, encoding: .utf8)
        _ = try runGit(["commit", "-am", "Move feature ref"], in: repository)
        let refreshed = try await service.currentComparisonFingerprint(base: base, head: head, in: repository)
        XCTAssertNotEqual(refreshed, initialFingerprint)
    }

    func testHistorySearchUsesTypedPathAndScopeFilters() async throws {
        let repository = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        try "let value = 2\n".write(to: repository.appending(path: "Example.swift"), atomically: true, encoding: .utf8)
        _ = try runGit(["commit", "-am", "Fix parser state"], in: repository)
        let search = try XCTUnwrap(RepositoryAIHistorySearch(
            query: "parser",
            author: "Repository AI Test",
            path: "Example.swift",
            scope: .currentBranch,
            limit: 5
        ))

        let result = try await GitStatusService.shared.searchHistory(search, in: repository, characterBudget: 2_000)

        XCTAssertEqual(result.commits.count, 1)
        XCTAssertEqual(result.commits.first?.subject, "Fix parser state")
        XCTAssertEqual(result.commits.first?.paths, ["Example.swift"])
        XCTAssertNil(RepositoryAIHistorySearch(query: "x", path: "../secret"))
        XCTAssertNil(RepositoryAIRef("HEAD~1"))
    }

    private func makeRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory.appending(path: "repository-ai-analysis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        _ = try runGit(["init", "-b", "main"], in: repository)
        _ = try runGit(["config", "user.email", "test@example.com"], in: repository)
        _ = try runGit(["config", "user.name", "Repository AI Test"], in: repository)
        try "let value = 1\n".write(to: repository.appending(path: "Example.swift"), atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Example.swift"], in: repository)
        _ = try runGit(["commit", "-m", "Initial"], in: repository)
        return repository
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GitError.commandFailed("test Git failure") }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
