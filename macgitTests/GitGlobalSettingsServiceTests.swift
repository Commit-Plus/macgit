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

final class GitGlobalSettingsServiceTests: XCTestCase {
    func testLoadReadsGitVersionAndGlobalConfiguration() async throws {
        let runner = GlobalSettingsRecordingRunner(
            responses: [
                ["--version"]: "git version 2.50.1\n",
                ["config", "--global", "--get", "user.name"]: "Ada Lovelace\n",
                ["config", "--global", "--get", "user.email"]: "ada@example.com\n",
                ["config", "--global", "--get", "init.defaultBranch"]: "trunk\n",
                ["config", "--global", "--get", "fetch.prune"]: "true\n",
                ["config", "--global", "--get", "push.autoSetupRemote"]: "yes\n",
                ["config", "--global", "--get", "core.excludesFile"]: "~/.gitignore_global\n"
            ]
        )
        let service = GitStatusService(runner: runner)

        let settings = try await service.loadGlobalGitSettings()

        XCTAssertEqual(settings.version, "git version 2.50.1")
        XCTAssertFalse(settings.executablePath.isEmpty)
        XCTAssertEqual(settings.userName, "Ada Lovelace")
        XCTAssertEqual(settings.userEmail, "ada@example.com")
        XCTAssertEqual(settings.defaultBranchName, "trunk")
        XCTAssertTrue(settings.pruneOnFetch)
        XCTAssertTrue(settings.autoSetupRemote)
        XCTAssertEqual(settings.excludesFilePath, "~/.gitignore_global")
    }

    func testUpdateWritesValidatedGlobalConfiguration() async throws {
        let runner = GlobalSettingsRecordingRunner()
        let service = GitStatusService(runner: runner)
        let settings = GlobalGitSettings(
            executablePath: "/usr/bin/git",
            version: "git version 2.50.1",
            userName: "Ada Lovelace",
            userEmail: "ada@example.com",
            defaultBranchName: "main",
            pruneOnFetch: true,
            autoSetupRemote: false,
            excludesFilePath: "~/.config/git/ignore"
        )

        try await service.updateGlobalGitSettings(settings)

        let calls = await runner.recordedArguments()
        XCTAssertEqual(
            calls,
            [
                ["check-ref-format", "--branch", "main"],
                ["config", "--global", "user.name", "Ada Lovelace"],
                ["config", "--global", "user.email", "ada@example.com"],
                ["config", "--global", "init.defaultBranch", "main"],
                ["config", "--global", "fetch.prune", "true"],
                ["config", "--global", "push.autoSetupRemote", "false"],
                ["config", "--global", "core.excludesFile", "~/.config/git/ignore"]
            ]
        )
    }

    func testUpdateRejectsInvalidIdentityBeforeRunningGit() async {
        let runner = GlobalSettingsRecordingRunner()
        let service = GitStatusService(runner: runner)
        var settings = GlobalGitSettings.empty
        settings.userName = "Ada Lovelace"
        settings.userEmail = "invalid email"

        do {
            try await service.updateGlobalGitSettings(settings)
            XCTFail("Expected invalid email to be rejected.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("valid email"))
        }

        let calls = await runner.recordedArguments()
        XCTAssertTrue(calls.isEmpty)
    }
}

private actor GlobalSettingsRecordingRunner: GitCommandRunning {
    private let responses: [[String]: String]
    private var calls: [[String]] = []

    init(responses: [[String]: String] = [:]) {
        self.responses = responses
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls.append(arguments)
        return responses[arguments] ?? ""
    }

    func recordedArguments() -> [[String]] {
        calls
    }
}
