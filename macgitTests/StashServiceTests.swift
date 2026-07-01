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

final class StashServiceTests: XCTestCase {
    func testListStashesParsesRefBranchAndDescription() async throws {
        let repoURL = try makeTempRepoWithOneStash(message: "test stash")
        let stashes = await GitStatusService.shared.stashes(in: repoURL)

        XCTAssertEqual(stashes.count, 1)
        XCTAssertEqual(stashes[0].ref, "stash@{0}")
        XCTAssertEqual(stashes[0].branchName, "main")
        XCTAssertEqual(stashes[0].description, "test stash")
        XCTAssertEqual(stashes[0].displayTitle, "On main : test stash")
    }

    func testStashDiffReturnsHunksForModifiedFile() async throws {
        let repoURL = try makeTempRepoWithOneStash(message: "diff me")
        let hunks = await GitStatusService.shared.diff(for: "tracked.txt", in: "stash@{0}", in: repoURL)

        XCTAssertFalse(hunks.isEmpty)
        XCTAssertTrue(hunks.flatMap(\.lines).contains { $0.text == "working tree change" })
    }

    func testApplyStashWithDeleteAppliesChangesAndRemovesTheStash() async throws {
        let repoURL = try makeTempRepoWithOneStash(message: "delete me")
        try await GitStatusService.shared.applyStash(ref: "stash@{0}", dropAfterApplying: true, in: repoURL)

        let trackedFile = repoURL.appendingPathComponent("tracked.txt")
        let content = try String(contentsOf: trackedFile, encoding: .utf8)
        XCTAssertEqual(content, "working tree change\n")

        let stashes = await GitStatusService.shared.stashes(in: repoURL)
        XCTAssertTrue(stashes.isEmpty)
    }

    func testDropStashRemovesTheStashWithoutChangingTheWorkingTree() async throws {
        let repoURL = try makeTempRepoWithOneStash(message: "drop me")
        try await GitStatusService.shared.dropStash(ref: "stash@{0}", in: repoURL)

        let trackedFile = repoURL.appendingPathComponent("tracked.txt")
        let content = try String(contentsOf: trackedFile, encoding: .utf8)
        XCTAssertEqual(content, "base\n")

        let stashes = await GitStatusService.shared.stashes(in: repoURL)
        XCTAssertTrue(stashes.isEmpty)
    }

    func testStashSelectedPathsLeavesUnrelatedChangesIntact() async throws {
        let repoURL = try makeTempRepoWithTwoTrackedAndTwoUntracked()
        let options = GitStatusService.StashOptions(
            message: "Selected files",
            paths: ["tracked.txt", "new.txt"],
            includeUntracked: true
        )

        try await GitStatusService.shared.stash(options: options, in: repoURL)

        let stashes = await GitStatusService.shared.stashes(in: repoURL)
        XCTAssertEqual(stashes.count, 1)
        XCTAssertEqual(stashes[0].description, "Selected files")

        let tracked = try String(contentsOf: repoURL.appendingPathComponent("tracked.txt"), encoding: .utf8)
        XCTAssertEqual(tracked, "base\n")

        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("new.txt").path))

        let otherTracked = try String(contentsOf: repoURL.appendingPathComponent("other.txt"), encoding: .utf8)
        XCTAssertEqual(otherTracked, "tracked edit\n")

        let otherUntracked = try String(contentsOf: repoURL.appendingPathComponent("other-new.txt"), encoding: .utf8)
        XCTAssertEqual(otherUntracked, "untracked content\n")

        try await GitStatusService.shared.applyStash(ref: "stash@{0}", in: repoURL)

        let restoredTracked = try String(contentsOf: repoURL.appendingPathComponent("tracked.txt"), encoding: .utf8)
        XCTAssertEqual(restoredTracked, "working tree change\n")
        let restoredUntracked = try String(contentsOf: repoURL.appendingPathComponent("new.txt"), encoding: .utf8)
        XCTAssertEqual(restoredUntracked, "untracked content\n")
    }

    // MARK: - Helpers

    private func makeTempRepoWithOneStash(message: String) throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-stash-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)

        let trackedFile = repoURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial commit"], in: repoURL)

        try "working tree change\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["stash", "push", "-m", message], in: repoURL)

        return repoURL
    }

    private func makeTempRepoWithTwoTrackedAndTwoUntracked() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-stash-selected-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)

        let trackedFile = repoURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        let otherTracked = repoURL.appendingPathComponent("other.txt")
        try "base\n".write(to: otherTracked, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt", "other.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial commit"], in: repoURL)

        try "working tree change\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try "tracked edit\n".write(to: otherTracked, atomically: true, encoding: .utf8)
        try "untracked content\n".write(to: repoURL.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        try "untracked content\n".write(to: repoURL.appendingPathComponent("other-new.txt"), atomically: true, encoding: .utf8)

        return repoURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
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
    }
}
