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

final class GitFlowLitePhase4Tests: XCTestCase {
    func testOldConfigurationDefaultsToCurrentWorkingCopy() throws {
        let data = Data(#"{"isEnabled":true,"mainBranch":"main","developBranch":"develop"}"#.utf8)
        let configuration = try JSONDecoder().decode(GitFlowConfiguration.self, from: data)

        XCTAssertEqual(configuration.defaultStartDestination, .currentWorkingCopy)
    }

    func testConfigurationRoundTripsNewWorktreeDefaultThroughLinkedWorktree() async throws {
        let repositoryURL = try makeRepository()
        let linkedURL = siblingPath(for: repositoryURL, suffix: "linked")
        defer { cleanUp(repositoryURL, linkedURL) }
        try runGit(["worktree", "add", linkedURL.path, "develop"], in: repositoryURL)

        let configuration = GitFlowConfiguration(
            isEnabled: true,
            defaultStartDestination: .newWorktree
        )
        let store = GitFlowConfigurationStore()
        try await store.save(configuration, in: repositoryURL)

        let loadedConfiguration = await store.configuration(in: linkedURL)
        XCTAssertEqual(loadedConfiguration, configuration)
    }

    func testPlannerCarriesDestinationPathAndTrimmedLabel() throws {
        let path = URL(fileURLWithPath: "/tmp/commitplus-phase-4", isDirectory: true)
        let plan = try GitFlowPlanner().startPlan(
            kind: .hotfix,
            topicName: "2.0.1",
            configuration: GitFlowConfiguration(isEnabled: true),
            destination: .newWorktree,
            worktreePath: path,
            worktreeLabel: "  Urgent fix  "
        )

        XCTAssertEqual(plan.branchName, "hotfix/2.0.1")
        XCTAssertEqual(plan.baseBranch, "main")
        XCTAssertEqual(plan.destination, .newWorktree)
        XCTAssertEqual(plan.worktreePath, path)
        XCTAssertEqual(plan.worktreeLabel, "Urgent fix")
    }

    func testNewWorktreeStartAllowsDirtyCurrentWorkingCopyAndLeavesItUnchanged() async throws {
        let repositoryURL = try makeRepository()
        let worktreeURL = siblingPath(for: repositoryURL, suffix: "feature")
        defer { cleanUp(repositoryURL, worktreeURL) }
        try "dirty\n".write(
            to: repositoryURL.appendingPathComponent("untracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        let originalHead = try runGitOutput(["rev-parse", "HEAD"], in: repositoryURL)
        let plan = try GitFlowPlanner().startPlan(
            kind: .feature,
            topicName: "worktree-start",
            configuration: GitFlowConfiguration(isEnabled: true),
            destination: .newWorktree,
            worktreePath: worktreeURL,
            worktreeLabel: "Phase 4"
        )

        let result = try await GitFlowService().start(plan, in: repositoryURL)

        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        XCTAssertEqual(currentBranch, "main")
        XCTAssertEqual(try runGitOutput(["rev-parse", "HEAD"], in: repositoryURL), originalHead)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repositoryURL.appendingPathComponent("untracked.txt").path))
        let worktreeBranch = await GitStatusService.shared.currentBranch(in: worktreeURL)
        XCTAssertEqual(worktreeBranch, "feature/worktree-start")
        XCTAssertEqual(result.placement, .newWorktree(path: worktreeURL.standardizedFileURL, label: "Phase 4"))
        let entries = await GitStatusService.shared.worktreesWithLabels(in: repositoryURL)
        XCTAssertEqual(entries.first(where: { $0.branch == "feature/worktree-start" })?.label, "Phase 4")
    }

    func testNewWorktreeStartRejectsExistingPathBeforeCreatingBranch() async throws {
        let repositoryURL = try makeRepository()
        let worktreeURL = siblingPath(for: repositoryURL, suffix: "existing")
        defer { cleanUp(repositoryURL, worktreeURL) }
        try FileManager.default.createDirectory(at: worktreeURL, withIntermediateDirectories: true)
        let plan = GitFlowStartPlan(
            kind: .bugfix,
            branchName: "bugfix/existing-path",
            baseBranch: "develop",
            destination: .newWorktree,
            worktreePath: worktreeURL
        )

        do {
            _ = try await GitFlowService().start(plan, in: repositoryURL)
            XCTFail("Expected the existing path to be rejected")
        } catch {
            XCTAssertEqual(error as? GitFlowStartError, .worktreePathAlreadyExists(worktreeURL.path))
        }
        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertFalse(branches.contains("bugfix/existing-path"))
    }

    func testUndoAndRedoWorktreeStartPreservePathBranchAndLabel() async throws {
        let repositoryURL = try makeRepository()
        let worktreeURL = siblingPath(for: repositoryURL, suffix: "undo")
        defer { cleanUp(repositoryURL, worktreeURL) }
        let plan = GitFlowStartPlan(
            kind: .release,
            branchName: "release/3.0.0",
            baseBranch: "develop",
            destination: .newWorktree,
            worktreePath: worktreeURL,
            worktreeLabel: "Release 3"
        )
        let result = try await GitFlowService().start(plan, in: repositoryURL)
        let executor = GitUndoExecutor()

        try await executor.execute(
            .removeGitFlowWorktree(path: worktreeURL, branch: plan.branchName, expectedTip: result.createdTip),
            in: repositoryURL
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeURL.path))
        let branchesAfterUndo = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertFalse(branchesAfterUndo.contains(plan.branchName))

        try await executor.execute(
            .recreateGitFlowWorktree(
                path: worktreeURL,
                branch: plan.branchName,
                baseTip: result.baseTip,
                label: plan.worktreeLabel
            ),
            in: repositoryURL
        )
        let restoredBranch = await GitStatusService.shared.currentBranch(in: worktreeURL)
        XCTAssertEqual(restoredBranch, plan.branchName)
        let entries = await GitStatusService.shared.worktreesWithLabels(in: repositoryURL)
        XCTAssertEqual(entries.first(where: { $0.branch == plan.branchName })?.label, "Release 3")
    }

    func testUndoRefusesDirtyAndAdvancedWorktreeWithoutRemovingIt() async throws {
        let repositoryURL = try makeRepository()
        let worktreeURL = siblingPath(for: repositoryURL, suffix: "guard")
        defer { cleanUp(repositoryURL, worktreeURL) }
        let plan = GitFlowStartPlan(
            kind: .feature,
            branchName: "feature/guarded",
            baseBranch: "develop",
            destination: .newWorktree,
            worktreePath: worktreeURL
        )
        let result = try await GitFlowService().start(plan, in: repositoryURL)
        try "dirty\n".write(
            to: worktreeURL.appendingPathComponent("dirty.txt"),
            atomically: true,
            encoding: .utf8
        )

        do {
            try await GitUndoExecutor().execute(
                .removeGitFlowWorktree(path: worktreeURL, branch: plan.branchName, expectedTip: result.createdTip),
                in: repositoryURL
            )
            XCTFail("Expected dirty worktree guard")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktreeURL.path))
        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertTrue(branches.contains(plan.branchName))
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-git-flow-phase-4-\(UUID().uuidString)", isDirectory: true)
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
        try runGit(["branch", "develop"], in: repositoryURL)
        return repositoryURL
    }

    private func siblingPath(for repositoryURL: URL, suffix: String) -> URL {
        repositoryURL.deletingLastPathComponent()
            .appendingPathComponent("\(repositoryURL.lastPathComponent)-\(suffix)", isDirectory: true)
    }

    private func cleanUp(_ urls: URL...) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        _ = try runGitOutput(arguments, in: repositoryURL)
    }

    private func runGitOutput(_ arguments: [String], in repositoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            throw GitError.commandFailed(message)
        }
        return String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
