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

final class RepositoryAIGitCommandPolicyTests: XCTestCase {
    func testAllowsStagedDiffAndInjectsSafetyArguments() throws {
        let arguments = try RepositoryAIGitCommandPolicy.validatedArguments([
            "diff", "--cached", "--name-status", "--unified=3",
        ])

        XCTAssertEqual(arguments, [
            "--no-pager",
            "-c", "color.ui=false",
            "-c", "core.pager=cat",
            "diff", "--no-ext-diff", "--no-textconv",
            "--cached", "--name-status", "--unified=3",
        ])
    }

    func testAllowsNormalReadOnlyGitOptionsAndPathspecs() throws {
        let diff = try RepositoryAIGitCommandPolicy.validatedArguments([
            "diff", "--cached", "--word-diff=plain", "--", "Sources/**/*.swift",
        ])
        XCTAssertEqual(Array(diff.suffix(4)), [
            "--cached", "--word-diff=plain", "--", "Sources/**/*.swift",
        ])

        let log = try RepositoryAIGitCommandPolicy.validatedArguments([
            "log", "--all", "--decorate", "--pretty=format:%H%x09%s", "-25",
        ])
        XCTAssertEqual(Array(log.suffix(4)), [
            "--all", "--decorate", "--pretty=format:%H%x09%s", "-25",
        ])
    }

    func testRejectsMutatingAndNetworkCommands() {
        assertUnsupported(["add", "--all"])
        assertUnsupported(["reset", "--hard", "HEAD"])
        assertUnsupported(["push", "origin", "main"])
        assertUnsupported(["fetch", "origin"])
    }

    func testRejectsGlobalOverridesAndOutputFileOption() {
        assertUnsupported(["-c", "alias.x=!sh", "status"])
        assertUnsupported(["diff", "--output=/tmp/result"])
        assertUnsupported(["diff", "--no-index", "/tmp/a", "/tmp/b"])
        assertUnsupported(["show", "--ext-diff", "HEAD"])
        assertUnsupported(["cat-file", "--filters", "--path=Sources/App.swift", "HEAD:Sources/App.swift"])
    }

    func testRejectsUnsafeArgumentTransport() {
        assertUnsupported(["show", "HEAD\n--format=raw"])
        assertUnsupported(["merge-base", "--git-dir=/tmp/other", "main", "origin/main"])
        assertUnsupported(["diff", "--textconv", "HEAD"])
    }

    func testExecutorReturnsGitFailureAsToolResult() async throws {
        let runner = RecordingRepositoryAIGitRunner(result: .failure(.commandFailed("unknown revision")))
        let service = GitStatusService(runner: runner)
        let executor = RepositoryAIGitCommandExecutor(gitService: service)

        let result = try await executor.execute(
            arguments: ["show", "missing"],
            in: URL(fileURLWithPath: "/tmp/repository-ai"),
            outputCharacterLimit: 1_000
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.output, "unknown revision")
        XCTAssertEqual(result.displayCommand, "git show missing")
        let recorded = await runner.recordedArguments()
        XCTAssertEqual(recorded.last, "missing")
        XCTAssertTrue(recorded.contains("--no-ext-diff"))
    }

    private func assertUnsupported(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try RepositoryAIGitCommandPolicy.validatedArguments(arguments), file: file, line: line) { error in
            XCTAssertTrue(error is RepositoryAIGitCommandError, file: file, line: line)
        }
    }
}

private actor RecordingRepositoryAIGitRunner: GitCommandRunning {
    private let result: Result<String, GitError>
    private var arguments = [String]()

    init(result: Result<String, GitError>) {
        self.result = result
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        self.arguments = arguments
        return try result.get()
    }

    func recordedArguments() -> [String] {
        arguments
    }
}
