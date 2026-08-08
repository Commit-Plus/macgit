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

final class GitFlowLitePhase3Tests: XCTestCase {
    func testPlannerCreatesReleaseAndHotfixFinishPlans() throws {
        let configuration = GitFlowConfiguration(isEnabled: true)

        XCTAssertEqual(
            try GitFlowPlanner().finishPlan(
                kind: .release,
                currentBranch: "release/2.1.0",
                configuration: configuration
            ),
            GitFlowFinishPlan(
                kind: .release,
                sourceBranch: "release/2.1.0",
                targetBranch: "main",
                secondaryTargetBranch: "develop",
                tagName: "2.1.0",
                createTag: true,
                deleteSourceBranch: true
            )
        )
        XCTAssertEqual(
            try GitFlowPlanner().finishPlan(
                kind: .hotfix,
                currentBranch: "hotfix/2.1.1",
                configuration: configuration
            ),
            GitFlowFinishPlan(
                kind: .hotfix,
                sourceBranch: "hotfix/2.1.1",
                targetBranch: "main",
                secondaryTargetBranch: "develop",
                tagName: "2.1.1",
                createTag: true,
                deleteSourceBranch: true
            )
        )
    }

    func testFinishReleaseMergesMainAndDevelopCreatesAnnotatedTagAndDeletesSource() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createTopicCommit(branch: "release/2.1.0", base: "develop", contents: "release\n", in: repositoryURL)

        let result = try await GitFlowService().finish(
            GitFlowFinishPlan(
                kind: .release,
                sourceBranch: "release/2.1.0",
                targetBranch: "main",
                secondaryTargetBranch: "develop",
                tagName: "2.1.0",
                createTag: true,
                deleteSourceBranch: true
            ),
            in: repositoryURL
        )

        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        let targetBranches = result.targetResults.map { $0.branch }
        let createdTagName = result.createdTagName
        XCTAssertEqual(targetBranches, ["main", "develop"])
        XCTAssertEqual(createdTagName, "2.1.0")
        XCTAssertFalse(branches.contains("release/2.1.0"))
        XCTAssertEqual(try gitOutput(["rev-parse", "2.1.0^{commit}"], in: repositoryURL), try gitOutput(["rev-parse", "main"], in: repositoryURL))
        XCTAssertEqual(try gitOutput(["cat-file", "-t", "2.1.0"], in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines), "tag")
    }

    func testFinishHotfixMergesMainAndDevelop() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createTopicCommit(branch: "hotfix/2.1.1", base: "main", contents: "hotfix\n", in: repositoryURL)

        let result = try await GitFlowService().finish(
            GitFlowFinishPlan(
                kind: .hotfix,
                sourceBranch: "hotfix/2.1.1",
                targetBranch: "main",
                secondaryTargetBranch: "develop",
                tagName: "2.1.1",
                createTag: true,
                deleteSourceBranch: true
            ),
            in: repositoryURL
        )

        let targetBranches = result.targetResults.map { $0.branch }
        let createdTagName = result.createdTagName
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        XCTAssertEqual(targetBranches, ["main", "develop"])
        XCTAssertEqual(createdTagName, "2.1.1")
        XCTAssertEqual(currentBranch, "develop")
    }

    func testFinishReleaseStopsBeforeExistingTag() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createTopicCommit(branch: "release/2.1.0", base: "develop", contents: "release\n", in: repositoryURL)
        try runGit(["tag", "2.1.0"], in: repositoryURL)

        do {
            _ = try await GitFlowService().finish(
                GitFlowFinishPlan(
                    kind: .release,
                    sourceBranch: "release/2.1.0",
                    targetBranch: "main",
                    secondaryTargetBranch: "develop",
                    tagName: "2.1.0",
                    createTag: true,
                    deleteSourceBranch: true
                ),
                in: repositoryURL
            )
            XCTFail("Expected tag collision")
        } catch {
            XCTAssertEqual(error as? GitFlowFinishError, .tagAlreadyExists("2.1.0"))
        }
    }

    func testReleaseConflictLeavesCheckpointForResumeOrAbort() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createTopicCommit(branch: "release/2.1.0", base: "develop", contents: "release\n", in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
        try "main\n".write(to: repositoryURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "main conflict"], in: repositoryURL)
        try runGit(["checkout", "release/2.1.0"], in: repositoryURL)

        do {
            _ = try await GitFlowService().finish(
                GitFlowFinishPlan(
                    kind: .release,
                    sourceBranch: "release/2.1.0",
                    targetBranch: "main",
                    secondaryTargetBranch: "develop",
                    tagName: "2.1.0",
                    createTag: true,
                    deleteSourceBranch: true
                ),
                in: repositoryURL
            )
            XCTFail("Expected conflict")
        } catch {
            let checkpoint = await GitFlowRecoveryStore().checkpoint(in: repositoryURL)
            let isMergeInProgress = await GitStatusService.shared.isMergeInProgress(in: repositoryURL)
            let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
            XCTAssertNotNil(checkpoint)
            XCTAssertEqual(checkpoint?.phase, .primaryMerge)
            XCTAssertTrue(isMergeInProgress)
            XCTAssertEqual(currentBranch, "main")
        }
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-git-flow-phase-3-\(UUID().uuidString)", isDirectory: true)
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

    private func createTopicCommit(branch: String, base: String, contents: String, in repositoryURL: URL) throws {
        try runGit(["checkout", base], in: repositoryURL)
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
