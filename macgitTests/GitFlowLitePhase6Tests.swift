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

@MainActor
final class GitFlowLitePhase6Tests: XCTestCase {
    func testBranchRoleResolverCoversExactAndTopicRoles() {
        let resolver = GitFlowBranchRoleResolver()
        let configuration = GitFlowConfiguration(isEnabled: true)

        XCTAssertEqual(resolver.role(for: "main", configuration: configuration), .main)
        XCTAssertEqual(resolver.role(for: "develop", configuration: configuration), .develop)
        XCTAssertEqual(resolver.role(for: "feature/search", configuration: configuration), .feature)
        XCTAssertEqual(resolver.role(for: "bugfix/sidebar", configuration: configuration), .bugfix)
        XCTAssertEqual(resolver.role(for: "release/4.0", configuration: configuration), .release)
        XCTAssertEqual(resolver.role(for: "hotfix/4.0.1", configuration: configuration), .hotfix)
        XCTAssertNil(resolver.role(for: "feature/", configuration: configuration))
        XCTAssertNil(resolver.role(for: "ordinary", configuration: configuration))
        XCTAssertNil(resolver.role(for: "main", configuration: GitFlowConfiguration()))
    }

    func testBranchRoleResolverUsesLongestOverlappingPrefixDeterministically() {
        let configuration = GitFlowConfiguration(
            isEnabled: true,
            featurePrefix: "topic/",
            bugfixPrefix: "topic/bug/"
        )
        let role = GitFlowBranchRoleResolver().role(
            for: "topic/bug/fix",
            configuration: configuration
        )
        XCTAssertEqual(role, .bugfix)
        XCTAssertThrowsError(try GitFlowPlanner().validate(configuration)) { error in
            XCTAssertEqual(
                error as? GitFlowPlannerError,
                .invalidConfiguration("Git Flow prefixes must not overlap. Choose clearly distinct prefix paths.")
            )
        }
    }

    func testInvalidRecoveryStateDisablesNewCommandsButNotLocalDisable() {
        let state = GitFlowCommandState(
            isEnabled: true,
            currentKind: .feature,
            operationInProgress: false,
            hasPendingFinish: false,
            hasInvalidRecoveryState: true
        )

        XCTAssertFalse(state.canStart(.feature))
        XCTAssertFalse(state.canFinish(.feature))
        XCTAssertTrue(state.canConfigure)
        XCTAssertFalse(state.canResumeOrAbortFinish)
    }

    func testConfigurationStoreDistinguishesMissingCorruptAndUnsupported() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let store = GitFlowConfigurationStore()

        assertNone(await store.loadResult(in: repositoryURL))
        let fileURL = try await store.configurationURL(in: repositoryURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        assertInvalid(await store.loadResult(in: repositoryURL), expected: .corrupt)

        try Data(#"{"schemaVersion":99,"isEnabled":true}"#.utf8).write(to: fileURL)
        assertInvalid(await store.loadResult(in: repositoryURL), expected: .unsupportedVersion(99))
    }

    func testOldConfigurationAndCheckpointRemainSupported() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let configurationStore = GitFlowConfigurationStore()
        let configurationURL = try await configurationStore.configurationURL(in: repositoryURL)
        try FileManager.default.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"isEnabled":true,"mainBranch":"main","developBranch":"develop"}"#.utf8)
            .write(to: configurationURL)
        if case .value(let configuration) = await configurationStore.loadResult(in: repositoryURL) {
            XCTAssertEqual(configuration.schemaVersion, 1)
            XCTAssertEqual(configuration.topicFinishStrategy, .mergeNoFastForward)
        } else {
            XCTFail("Expected the old configuration to decode")
        }

        let checkpointStore = GitFlowRecoveryStore()
        let checkpointURL = try await checkpointStore.checkpointURL(in: repositoryURL)
        let oldCheckpoint = #"{"plan":{"kind":"feature","sourceBranch":"feature/old","primaryTargetBranch":"develop","createTag":false,"deleteSourceBranch":true},"sourceTip":"source","targetResults":[],"phase":"primaryMerge"}"#
        try Data(oldCheckpoint.utf8).write(to: checkpointURL)
        if case .value(let checkpoint) = await checkpointStore.loadResult(in: repositoryURL) {
            XCTAssertEqual(checkpoint.schemaVersion, 1)
            XCTAssertEqual(checkpoint.phase, .primaryMerge)
        } else {
            XCTFail("Expected the old checkpoint to decode")
        }

        try Data(#"{"schemaVersion":99}"#.utf8).write(to: checkpointURL)
        assertInvalid(
            await checkpointStore.loadResult(in: repositoryURL),
            expected: .unsupportedVersion(99)
        )
    }

    func testLinkedWorktreeSharesConfigurationAndCheckpointFromCommonDirectory() async throws {
        let repositoryURL = try makeRepository()
        let linkedURL = repositoryURL.deletingLastPathComponent()
            .appendingPathComponent("\(repositoryURL.lastPathComponent)-linked", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: linkedURL)
            try? FileManager.default.removeItem(at: repositoryURL)
        }
        try runGit(["worktree", "add", linkedURL.path, "develop"], in: repositoryURL)
        let configuration = GitFlowConfiguration(
            isEnabled: true,
            topicFinishStrategy: .rebaseFastForward
        )
        try await GitFlowConfigurationStore().save(configuration, in: repositoryURL)
        let sourceTip = try gitOutput(["rev-parse", "main"], in: repositoryURL)
        let checkpoint = GitFlowFinishCheckpoint(
            plan: GitFlowFinishPlan(
                kind: .feature,
                sourceBranch: "feature/shared",
                targetBranch: "develop",
                deleteSourceBranch: true
            ),
            sourceTip: sourceTip,
            targetResults: [],
            createdTagName: nil,
            phase: .primaryMerge
        )
        try await GitFlowRecoveryStore().save(checkpoint, in: repositoryURL)

        if case .value(let loaded) = await GitFlowConfigurationStore().loadResult(in: linkedURL) {
            XCTAssertEqual(loaded, configuration)
        } else {
            XCTFail("Expected linked worktree configuration")
        }
        if case .value(let loaded) = await GitFlowRecoveryStore().loadResult(in: linkedURL) {
            XCTAssertEqual(loaded, checkpoint)
        } else {
            XCTFail("Expected linked worktree checkpoint")
        }
    }

    func testCorruptCheckpointBlocksStartBeforeCreatingBranch() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        let recoveryStore = GitFlowRecoveryStore()
        let checkpointURL = try await recoveryStore.checkpointURL(in: repositoryURL)
        try FileManager.default.createDirectory(
            at: checkpointURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("broken".utf8).write(to: checkpointURL)
        let plan = GitFlowStartPlan(
            kind: .feature,
            branchName: "feature/blocked",
            baseBranch: "develop"
        )

        do {
            _ = try await GitFlowService().start(plan, in: repositoryURL)
            XCTFail("Expected corrupt recovery state to block Start")
        } catch {
            XCTAssertEqual(
                error as? GitFlowStartError,
                .invalidRecoveryState(GitFlowLocalStateIssue.corrupt.message)
            )
        }
        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertFalse(branches.contains("feature/blocked"))
    }

    func testAbortRefusesTargetDriftAndKeepsCheckpoint() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try runGit(["checkout", "develop"], in: repositoryURL)
        try runGit(["checkout", "-b", "release/4.0"], in: repositoryURL)
        try runGit(["commit", "--allow-empty", "-m", "release"], in: repositoryURL)
        let sourceTip = try gitOutput(["rev-parse", "HEAD"], in: repositoryURL)
        let mainBefore = try gitOutput(["rev-parse", "main"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
        try runGit(["commit", "--allow-empty", "-m", "finished primary"], in: repositoryURL)
        let mainAfter = try gitOutput(["rev-parse", "main"], in: repositoryURL)
        let checkpoint = GitFlowFinishCheckpoint(
            plan: GitFlowFinishPlan(
                kind: .release,
                sourceBranch: "release/4.0",
                targetBranch: "main",
                secondaryTargetBranch: "develop",
                tagName: nil,
                createTag: false,
                deleteSourceBranch: false
            ),
            sourceTip: sourceTip,
            targetResults: [
                GitFlowFinishTargetResult(
                    branch: "main",
                    tipBeforeMerge: mainBefore,
                    tipAfterMerge: mainAfter
                )
            ],
            createdTagName: nil,
            phase: .secondaryMerge
        )
        try await GitFlowRecoveryStore().save(checkpoint, in: repositoryURL)
        try runGit(["commit", "--allow-empty", "-m", "unexpected drift"], in: repositoryURL)

        do {
            try await GitFlowService().abortFinish(in: repositoryURL)
            XCTFail("Expected target drift guard")
        } catch {
            XCTAssertEqual(error as? GitFlowFinishError, .targetRefMoved("main"))
        }
        if case .value = await GitFlowRecoveryStore().loadResult(in: repositoryURL) {
            // Expected: manual recovery remains possible.
        } else {
            XCTFail("Abort must keep the checkpoint after ref drift")
        }
    }

    private func assertNone<T>(
        _ result: GitFlowLocalStateLoadResult<T>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .none = result else {
            XCTFail("Expected no saved state", file: file, line: line)
            return
        }
    }

    private func assertInvalid<T>(
        _ result: GitFlowLocalStateLoadResult<T>,
        expected: GitFlowLocalStateIssue,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .invalid(let issue) = result else {
            XCTFail("Expected invalid saved state", file: file, line: line)
            return
        }
        XCTAssertEqual(issue, expected, file: file, line: line)
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-git-flow-phase-6-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
        try runGit(["commit", "--allow-empty", "-m", "initial"], in: repositoryURL)
        try runGit(["branch", "develop"], in: repositoryURL)
        return repositoryURL
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
            let message = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            throw GitError.commandFailed(message)
        }
        return (String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
