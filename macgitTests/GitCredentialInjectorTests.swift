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

final class GitCredentialInjectorTests: XCTestCase {
    func testEnvironmentSetsGitTerminalPromptToZero() throws {
        let injection = try makeInjection()
        defer { injection.cleanup() }

        XCTAssertEqual(injection.environment["GIT_TERMINAL_PROMPT"], "0")
        XCTAssertNotNil(injection.environment["GIT_ASKPASS"])
    }

    func testAskpassHelperDoesNotContainTokenInFileName() throws {
        let injection = try makeInjection(token: "secret-token-123")
        defer { injection.cleanup() }

        let askpass = try XCTUnwrap(injection.environment["GIT_ASKPASS"])
        XCTAssertFalse(askpass.contains("secret-token-123"))
    }

    func testAskpassHelperReturnsUsernameForUsernamePrompt() throws {
        let injection = try makeInjection(username: "octocat", token: "secret-token")
        defer { injection.cleanup() }

        XCTAssertEqual(try runAskpass(injection, prompt: "Username for 'https://github.com':"), "octocat\n")
    }

    func testAskpassHelperReturnsTokenForPasswordPrompt() throws {
        let injection = try makeInjection(username: "octocat", token: "secret-token")
        defer { injection.cleanup() }

        XCTAssertEqual(try runAskpass(injection, prompt: "Password for 'https://octocat@github.com':"), "secret-token\n")
    }

    func testCleanupRemovesHelperFile() throws {
        let injection = try makeInjection()
        let askpass = try XCTUnwrap(injection.environment["GIT_ASKPASS"])
        let usernameFile = try XCTUnwrap(injection.environment["MACGIT_GIT_USERNAME_FILE"])
        let tokenFile = try XCTUnwrap(injection.environment["MACGIT_GIT_TOKEN_FILE"])

        injection.cleanup()

        XCTAssertFalse(FileManager.default.fileExists(atPath: askpass))
        XCTAssertFalse(FileManager.default.fileExists(atPath: usernameFile))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenFile))
    }

    private func makeInjection(
        username: String = "octocat",
        token: String = "secret-token"
    ) throws -> GitCredentialInjection {
        try TemporaryGitCredentialInjector().injection(for: GitCredential(username: username, token: token))
    }

    private func runAskpass(_ injection: GitCredentialInjection, prompt: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: try XCTUnwrap(injection.environment["GIT_ASKPASS"]))
        task.arguments = [prompt]
        task.environment = injection.environment

        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
