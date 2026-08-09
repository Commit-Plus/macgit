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

final class GitFlowDevelopBranchCreationTests: XCTestCase {
    @MainActor
    func testDevelopSheetPreservesRequestAcrossAsyncCallbackConversion() async throws {
        let request = GitFlowDevelopBranchRequest(name: "develop", startingPoint: "main")
        let sheet = CreateGitFlowDevelopBranchSheet(
            suggestedName: request.name,
            startingPoint: request.startingPoint,
            onCreate: { receivedRequest in
                XCTAssertTrue(receivedRequest === request)
                return receivedRequest.name
            },
            onCreated: { _ in }
        )

        let result = try await sheet.onCreate(request)

        XCTAssertEqual(result, "develop")
    }

    func testCreatesDevelopFromMainWithoutCheckingItOut() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }

        let branch = try await GitFlowService().createDevelopBranch(
            name: " develop ",
            startingPoint: "main",
            in: repositoryURL
        )
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        let mainTip = try await GitBranchUndoSupport().tip(of: "main", in: repositoryURL)
        let developTip = try await GitBranchUndoSupport().tip(of: "develop", in: repositoryURL)

        XCTAssertEqual(branch, "develop")
        XCTAssertEqual(currentBranch, "main")
        XCTAssertEqual(developTip, mainTip)
    }

    func testRejectsAnExistingDevelopBranch() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try runGit(["branch", "develop"], in: repositoryURL)

        do {
            _ = try await GitFlowService().createDevelopBranch(
                name: "develop",
                startingPoint: "main",
                in: repositoryURL
            )
            XCTFail("Expected existing branch validation to fail")
        } catch {
            XCTAssertEqual(
                error as? GitFlowDevelopBranchCreationError,
                .branchAlreadyExists("develop")
            )
        }
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-git-flow-develop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
        try "base\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], in: repositoryURL)
        try runGit(["commit", "-m", "initial"], in: repositoryURL)
        return repositoryURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let standardError = Pipe()
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            throw GitError.commandFailed(message)
        }
    }
}
