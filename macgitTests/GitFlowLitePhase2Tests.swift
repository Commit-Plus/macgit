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

final class GitFlowLitePhase2Tests: XCTestCase {
    func testPlannerCreatesFeatureAndBugfixFinishPlans() throws {
        let configuration = GitFlowConfiguration(isEnabled: true)

        XCTAssertEqual(
            try GitFlowPlanner().finishPlan(
                kind: .feature,
                currentBranch: "feature/sidebar",
                configuration: configuration
            ),
            GitFlowFinishPlan(
                kind: .feature,
                sourceBranch: "feature/sidebar",
                targetBranch: "develop",
                deleteSourceBranch: true
            )
        )
        XCTAssertThrowsError(
            try GitFlowPlanner().finishPlan(
                kind: .release,
                currentBranch: "release/2.0",
                configuration: configuration
            )
        )
    }

    func testFinishFeatureCreatesNoFastForwardMergeAndDeletesSource() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createTopicCommit(branch: "feature/sidebar", contents: "feature\n", in: repositoryURL)

        let plan = GitFlowFinishPlan(
            kind: .feature,
            sourceBranch: "feature/sidebar",
            targetBranch: "develop",
            deleteSourceBranch: true
        )
        let result = try await GitFlowService().finish(plan, in: repositoryURL)

        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertEqual(currentBranch, "develop")
        XCTAssertFalse(branches.contains("feature/sidebar"))
        XCTAssertTrue(result.didDeleteSourceBranch)
        XCTAssertEqual(try gitOutput(["rev-list", "--parents", "-n", "1", "HEAD"], in: repositoryURL).split(separator: " ").count, 3)
    }

    func testFinishBugfixCanKeepSourceBranch() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createTopicCommit(branch: "bugfix/status", contents: "bugfix\n", in: repositoryURL)

        let result = try await GitFlowService().finish(
            GitFlowFinishPlan(
                kind: .bugfix,
                sourceBranch: "bugfix/status",
                targetBranch: "develop",
                deleteSourceBranch: false
            ),
            in: repositoryURL
        )

        XCTAssertFalse(result.didDeleteSourceBranch)
        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertTrue(branches.contains("bugfix/status"))
    }

    func testFinishConflictPreservesSourceAndLeavesMergeForResolution() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createTopicCommit(branch: "feature/conflict", contents: "feature\n", in: repositoryURL)
        try runGit(["checkout", "develop"], in: repositoryURL)
        try "develop\n".write(to: repositoryURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "develop change"], in: repositoryURL)
        try runGit(["checkout", "feature/conflict"], in: repositoryURL)

        do {
            _ = try await GitFlowService().finish(
                GitFlowFinishPlan(
                    kind: .feature,
                    sourceBranch: "feature/conflict",
                    targetBranch: "develop",
                    deleteSourceBranch: true
                ),
                in: repositoryURL
            )
            XCTFail("Expected a merge conflict")
        } catch {
            let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
            let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
            let mergeInProgress = await GitStatusService.shared.isMergeInProgress(in: repositoryURL)
            XCTAssertEqual(currentBranch, "develop")
            XCTAssertTrue(branches.contains("feature/conflict"))
            XCTAssertTrue(mergeInProgress)
        }
    }

    func testSidebarStateDefaultsGitFlowToExpandedWhenDecodingOlderSettings() throws {
        let state = try JSONDecoder().decode(SidebarSectionState.self, from: Data("{}".utf8))
        XCTAssertTrue(state.gitFlowExpanded)
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-git-flow-phase-2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
        try "base\n".write(to: repositoryURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repositoryURL)
        try runGit(["commit", "-m", "initial"], in: repositoryURL)
        try runGit(["branch", "develop"], in: repositoryURL)
        return repositoryURL
    }

    private func createTopicCommit(branch: String, contents: String, in repositoryURL: URL) throws {
        try runGit(["checkout", "develop"], in: repositoryURL)
        try runGit(["checkout", "-b", branch], in: repositoryURL)
        try contents.write(to: repositoryURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "topic change"], in: repositoryURL)
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        _ = try gitOutput(arguments, in: repositoryURL)
    }

    private func gitOutput(_ arguments: [String], in repositoryURL: URL) throws -> String {
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
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw GitError.commandFailed(message)
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
