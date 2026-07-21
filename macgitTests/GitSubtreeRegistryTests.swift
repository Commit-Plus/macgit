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

final class GitSubtreeRegistryTests: XCTestCase {
    func testEmptyRegistryReturnsNoEntries() async throws {
        let repository = try makeRepository()

        let entries = try await GitSubtreeRegistry().entries(in: repository)

        XCTAssertEqual(entries, [])
    }

    func testRoundTripsEntriesThroughLocalGitConfig() async throws {
        let repository = try makeRepository()
        try makeDirectory("Packages/SharedKit", in: repository)
        let registry = GitSubtreeRegistry()
        let entry = GitSubtreeEntry(
            id: "packages-sharedkit",
            name: "SharedKit",
            path: "Packages/SharedKit",
            repository: "https://example.com/shared.git",
            branch: "main",
            squash: true,
            folderExists: false
        )

        try await registry.save(entry, in: repository)

        XCTAssertEqual(try runGit(["config", "--local", "--get", "commitplus-subtree.packages-sharedkit.path"], in: repository), "Packages/SharedKit\n")
        let entries = try await registry.entries(in: repository)
        XCTAssertEqual(
            entries,
            [
                GitSubtreeEntry(
                    id: "packages-sharedkit",
                    name: "SharedKit",
                    path: "Packages/SharedKit",
                    repository: "https://example.com/shared.git",
                    branch: "main",
                    squash: true,
                    folderExists: true
                )
            ]
        )
    }

    func testEntriesAreSortedByPath() async throws {
        let repository = try makeRepository()
        let registry = GitSubtreeRegistry()

        try await registry.save(entry(id: "z", path: "Vendor/Zed"), in: repository)
        try await registry.save(entry(id: "a", path: "Packages/Alpha"), in: repository)

        let entries = try await registry.entries(in: repository)
        XCTAssertEqual(entries.map(\.path), ["Packages/Alpha", "Vendor/Zed"])
    }

    func testMakeEntryGeneratesStableIDWithCollisionSuffix() async throws {
        let repository = try makeRepository()
        let registry = GitSubtreeRegistry()
        try await registry.save(entry(id: "packages-sharedkit", path: "Existing/SharedKit"), in: repository)

        let created = try await registry.makeEntry(
            name: "SharedKit",
            path: "Packages/SharedKit",
            repository: "https://example.com/shared.git",
            branch: "main",
            squash: false,
            in: repository
        )

        XCTAssertEqual(created.id, "packages-sharedkit-2")
        XCTAssertEqual(created.path, "Packages/SharedKit")
    }

    func testIncompleteEntriesAreOmitted() async throws {
        let repository = try makeRepository()
        try runGit(["config", "--local", "commitplus-subtree.missing.path", "Packages/Missing"], in: repository)
        try runGit(["config", "--local", "commitplus-subtree.missing.repository", "https://example.com/missing.git"], in: repository)
        try runGit(["config", "--local", "commitplus-subtree.complete.name", "Complete"], in: repository)
        try runGit(["config", "--local", "commitplus-subtree.complete.path", "Packages/Complete"], in: repository)
        try runGit(["config", "--local", "commitplus-subtree.complete.repository", "https://example.com/complete.git"], in: repository)
        try runGit(["config", "--local", "commitplus-subtree.complete.branch", "main"], in: repository)
        try runGit(["config", "--local", "commitplus-subtree.complete.squash", "false"], in: repository)

        let entries = try await GitSubtreeRegistry().entries(in: repository)

        XCTAssertEqual(entries.map(\.id), ["complete"])
    }

    func testRejectsDuplicateAndOverlappingPaths() async throws {
        let repository = try makeRepository()
        let registry = GitSubtreeRegistry()
        try await registry.save(entry(id: "shared", path: "Packages/SharedKit"), in: repository)

        await XCTAssertThrowsErrorAsync({
            try await registry.save(entry(id: "duplicate", path: "Packages/SharedKit"), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .duplicatePath("Packages/SharedKit"))
        }
        await XCTAssertThrowsErrorAsync({
            try await registry.save(entry(id: "child", path: "Packages/SharedKit/Core"), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .overlappingPath("Packages/SharedKit"))
        }
        await XCTAssertThrowsErrorAsync({
            try await registry.save(entry(id: "parent", path: "Packages"), in: repository)
        }) { error in
            XCTAssertEqual(error as? GitSubtreeRegistryError, .overlappingPath("Packages/SharedKit"))
        }
    }

    func testReportsStaleMissingFolderOnRead() async throws {
        let repository = try makeRepository()
        let registry = GitSubtreeRegistry()
        try await registry.save(entry(id: "missing", path: "Packages/Missing"), in: repository)

        let entries = try await registry.entries(in: repository)
        XCTAssertEqual(entries.first?.folderExists, false)
    }

    func testEditsExistingEntryAndAllowsSamePathForSameID() async throws {
        let repository = try makeRepository()
        let registry = GitSubtreeRegistry()
        try await registry.save(entry(id: "shared", path: "Packages/SharedKit"), in: repository)

        try await registry.save(
            GitSubtreeEntry(
                id: "shared",
                name: "SharedKit Renamed",
                path: "Packages/SharedKit",
                repository: "https://example.com/new.git",
                branch: "release",
                squash: true,
                folderExists: false
            ),
            in: repository
        )

        let entries = try await registry.entries(in: repository)
        let edited = try XCTUnwrap(entries.first)
        XCTAssertEqual(edited.name, "SharedKit Renamed")
        XCTAssertEqual(edited.repository, "https://example.com/new.git")
        XCTAssertEqual(edited.branch, "release")
        XCTAssertTrue(edited.squash)
    }

    func testRemoveDeletesConfigSection() async throws {
        let repository = try makeRepository()
        let registry = GitSubtreeRegistry()
        try await registry.save(entry(id: "shared", path: "Packages/SharedKit"), in: repository)

        try await registry.remove(id: "shared", in: repository)

        let entries = try await registry.entries(in: repository)
        XCTAssertEqual(entries, [])
    }

    private func entry(id: String, path: String) -> GitSubtreeEntry {
        GitSubtreeEntry(
            id: id,
            name: id,
            path: path,
            repository: "https://example.com/\(id).git",
            branch: "main",
            squash: false,
            folderExists: false
        )
    }

    private func makeRepository() throws -> URL {
        let root = try makeTemporaryDirectory()
        let repository = root.appendingPathComponent("Repository", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repository)
        try runGit(["config", "user.name", "Commit Plus Tests"], in: repository)
        try runGit(["config", "user.email", "tests@example.com"], in: repository)
        return repository
    }

    private func makeDirectory(_ path: String, in repository: URL) throws {
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(path, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-subtree-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(String(data: errorData, encoding: .utf8) ?? "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> some Any,
    _ validation: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        validation(error)
    }
}
