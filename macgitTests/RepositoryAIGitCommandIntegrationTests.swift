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

final class RepositoryAIGitCommandIntegrationTests: XCTestCase {
    func testStagedDiffReadsIndexWithoutChangingRepositoryState() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let sourceURL = repositoryURL.appending(path: "Example.swift")
        try "let value = 2\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Example.swift"], in: repositoryURL)

        let headBefore = try runGit(["rev-parse", "HEAD"], in: repositoryURL)
        let statusBefore = try runGit(["status", "--porcelain=v1"], in: repositoryURL)
        let configBefore = try Data(contentsOf: repositoryURL.appending(path: ".git/config"))

        let result = try await RepositoryAIGitCommandExecutor().execute(
            arguments: ["diff", "--cached", "--unified=3"],
            in: repositoryURL,
            outputCharacterLimit: 8_000
        )

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains("+let value = 2"))
        XCTAssertEqual(try runGit(["rev-parse", "HEAD"], in: repositoryURL), headBefore)
        XCTAssertEqual(try runGit(["status", "--porcelain=v1"], in: repositoryURL), statusBefore)
        XCTAssertEqual(try Data(contentsOf: repositoryURL.appending(path: ".git/config")), configBefore)
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appending(path: "repository-ai-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        _ = try runGit(["init"], in: repositoryURL)
        _ = try runGit(["config", "user.email", "test@example.com"], in: repositoryURL)
        _ = try runGit(["config", "user.name", "Repository AI Test"], in: repositoryURL)
        try "let value = 1\n".write(
            to: repositoryURL.appending(path: "Example.swift"),
            atomically: true,
            encoding: .utf8
        )
        _ = try runGit(["add", "Example.swift"], in: repositoryURL)
        _ = try runGit(["commit", "-m", "Initial"], in: repositoryURL)
        return repositoryURL
    }

    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw GitError.commandFailed(error)
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}
