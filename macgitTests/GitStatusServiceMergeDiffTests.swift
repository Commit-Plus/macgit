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
import XCTest
@testable import macgit

@MainActor
final class GitStatusServiceMergeDiffTests: XCTestCase {
    func testChangedFilesForMergeCommitIsNotEmpty() async throws {
        let repoURL = try makeRepoWithMergeCommit()
        let head = try await GitStatusService.shared.tipHash(for: "main", in: repoURL)
        let commit = try XCTUnwrap(head)

        let changes = await GitStatusService.shared.changedFiles(in: commit, in: repoURL)

        XCTAssertFalse(changes.isEmpty, "Merge commit should list files changed relative to first parent")
        XCTAssertTrue(changes.contains { $0.path == "feature.txt" }, "Feature file should appear in merge changes")
    }

    func testDiffForMergeCommitFileIsNotEmpty() async throws {
        let repoURL = try makeRepoWithMergeCommit()
        let head = try await GitStatusService.shared.tipHash(for: "main", in: repoURL)
        let commit = try XCTUnwrap(head)

        let hunks = await GitStatusService.shared.diff(for: "feature.txt", in: commit, in: repoURL)

        XCTAssertFalse(hunks.isEmpty, "Merge commit should produce a diff against the first parent")
        let addedLines = hunks.flatMap { $0.lines }.filter { $0.type == .added }
        XCTAssertTrue(addedLines.contains { $0.text == "feature line" }, "Diff should contain the feature addition")
    }

    // MARK: - Helpers

    private func makeRepoWithMergeCommit() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-merge-diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)

        let baseFile = repoURL.appendingPathComponent("base.txt")
        try "base\n".write(to: baseFile, atomically: true, encoding: .utf8)
        try runGit(["add", "base.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)

        try runGit(["checkout", "-b", "feature"], in: repoURL)
        let featureFile = repoURL.appendingPathComponent("feature.txt")
        try "feature line\n".write(to: featureFile, atomically: true, encoding: .utf8)
        try runGit(["add", "feature.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature commit"], in: repoURL)

        try runGit(["checkout", "main"], in: repoURL)
        let mainFile = repoURL.appendingPathComponent("main.txt")
        try "main line\n".write(to: mainFile, atomically: true, encoding: .utf8)
        try runGit(["add", "main.txt"], in: repoURL)
        try runGit(["commit", "-m", "main advance"], in: repoURL)

        try runGit(["merge", "feature", "-m", "merge feature"], in: repoURL)
        return repoURL
    }

    @discardableResult
    private func runGit(_ arguments: [String], in repositoryURL: URL) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let outputData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "git failed"
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(output)")
        }
        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
