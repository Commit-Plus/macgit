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

final class GitSubmoduleDiscoveryTests: XCTestCase {
    func testRepositoryWithoutGitmodulesReturnsNoEntries() async throws {
        let root = try makeTemporaryDirectory()
        let repository = root.appendingPathComponent("parent", isDirectory: true)
        try createRepository(at: repository)

        let entries = try await GitStatusService.shared.submodules(in: repository)

        XCTAssertEqual(entries, [])
    }

    func testDiscoversInitializedCleanSubmodule() async throws {
        let setup = try makeParentWithSubmodule()

        let entries = try await GitStatusService.shared.submodules(in: setup.parent)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "SharedKit")
        XCTAssertEqual(entries[0].path, "Packages/SharedKit")
        XCTAssertEqual(entries[0].state, .clean)
        XCTAssertTrue(entries[0].isInitialized)
        XCTAssertEqual(entries[0].recordedCommit, entries[0].checkedOutCommit)
    }

    func testFreshCloneReportsUninitializedSubmodule() async throws {
        let setup = try makeParentWithSubmodule()
        let clone = setup.root.appendingPathComponent("clone", isDirectory: true)
        try runGit(["clone", setup.parent.path, clone.path], in: setup.root)

        let entries = try await GitStatusService.shared.submodules(in: clone)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].state, .uninitialized)
        XCTAssertFalse(entries[0].isInitialized)
        XCTAssertNil(entries[0].checkedOutCommit)
    }

    func testReportsModifiedSubmoduleWorkingTree() async throws {
        let setup = try makeParentWithSubmodule()
        let submodule = setup.parent.appendingPathComponent("Packages/SharedKit", isDirectory: true)
        try "changed\n".write(
            to: submodule.appendingPathComponent("shared.txt"),
            atomically: true,
            encoding: .utf8
        )

        let entries = try await GitStatusService.shared.submodules(in: setup.parent)

        XCTAssertEqual(entries[0].state, .modified)
    }

    func testReportsCheckedOutCommitDifferentFromRecordedGitlink() async throws {
        let setup = try makeParentWithSubmodule()
        let submodule = setup.parent.appendingPathComponent("Packages/SharedKit", isDirectory: true)
        try configureIdentity(in: submodule)
        try "next\n".write(
            to: submodule.appendingPathComponent("next.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "next.txt"], in: submodule)
        try runGit(["commit", "-m", "next"], in: submodule)

        let entries = try await GitStatusService.shared.submodules(in: setup.parent)

        XCTAssertEqual(entries[0].state, .newCommits)
        XCTAssertNotEqual(entries[0].recordedCommit, entries[0].checkedOutCommit)
    }

    func testDeletedInitializedCheckoutReportsMissing() async throws {
        let setup = try makeParentWithSubmodule()
        let submodule = setup.parent.appendingPathComponent("Packages/SharedKit", isDirectory: true)
        try FileManager.default.removeItem(at: submodule)

        let entries = try await GitStatusService.shared.submodules(in: setup.parent)

        XCTAssertEqual(entries[0].state, .missing)
        XCTAssertFalse(entries[0].isInitialized)
    }

    private func makeParentWithSubmodule() throws -> (root: URL, parent: URL) {
        let root = try makeTemporaryDirectory()
        let child = root.appendingPathComponent("SharedKit", isDirectory: true)
        let parent = root.appendingPathComponent("Parent", isDirectory: true)

        try createRepository(at: child)
        try "shared\n".write(
            to: child.appendingPathComponent("shared.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "shared.txt"], in: child)
        try runGit(["commit", "-m", "shared base"], in: child)

        try createRepository(at: parent)
        try "parent\n".write(
            to: parent.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], in: parent)
        try runGit(["commit", "-m", "parent base"], in: parent)
        try runGit(
            ["-c", "protocol.file.allow=always", "submodule", "add", "--name", "SharedKit", child.path, "Packages/SharedKit"],
            in: parent
        )
        try runGit(["commit", "-am", "add submodule"], in: parent)
        return (root, parent)
    }

    private func createRepository(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: url)
        try configureIdentity(in: url)
    }

    private func configureIdentity(in repository: URL) throws {
        try runGit(["config", "user.name", "Commit Plus Tests"], in: repository)
        try runGit(["config", "user.email", "tests@example.com"], in: repository)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-submodule-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let error = String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "Git command failed"
            throw GitError.commandFailed(error)
        }
    }
}
