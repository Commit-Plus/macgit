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
final class GitFlowLitePhase5Tests: XCTestCase {
    func testOldConfigurationAndFinishPlanDecodeWithSafeDefaults() throws {
        let configurationData = Data(#"{"isEnabled":true,"mainBranch":"main","developBranch":"develop"}"#.utf8)
        let configuration = try JSONDecoder().decode(GitFlowConfiguration.self, from: configurationData)

        XCTAssertEqual(configuration.topicFinishStrategy, .mergeNoFastForward)
        XCTAssertTrue(configuration.createReleaseTagOnFinish)
        XCTAssertTrue(configuration.createHotfixTagOnFinish)

        let planData = Data(
            #"{"kind":"feature","sourceBranch":"feature/old","primaryTargetBranch":"develop","createTag":false,"deleteSourceBranch":true}"#.utf8
        )
        let plan = try JSONDecoder().decode(GitFlowFinishPlan.self, from: planData)
        XCTAssertEqual(plan.strategy, .mergeNoFastForward)

        let checkpointData = Data(
            #"{"plan":{"kind":"feature","sourceBranch":"feature/old","primaryTargetBranch":"develop","createTag":false,"deleteSourceBranch":true},"sourceTip":"source","targetResults":[],"phase":"primaryMerge"}"#.utf8
        )
        let checkpoint = try JSONDecoder().decode(GitFlowFinishCheckpoint.self, from: checkpointData)
        XCTAssertEqual(checkpoint.phase, .primaryMerge)
        XCTAssertNil(checkpoint.rewrittenSourceTip)
    }

    func testPlannerResolvesTopicStrategyAndIndependentTagPreferences() throws {
        let configuration = GitFlowConfiguration(
            isEnabled: true,
            topicFinishStrategy: .rebaseFastForward,
            createReleaseTagOnFinish: false,
            createHotfixTagOnFinish: true
        )

        let feature = try GitFlowPlanner().finishPlan(
            kind: .feature,
            currentBranch: "feature/linear",
            configuration: configuration
        )
        let release = try GitFlowPlanner().finishPlan(
            kind: .release,
            currentBranch: "release/3.0.0",
            configuration: configuration
        )
        let hotfix = try GitFlowPlanner().finishPlan(
            kind: .hotfix,
            currentBranch: "hotfix/3.0.1",
            configuration: configuration
        )

        XCTAssertEqual(feature.strategy, .rebaseFastForward)
        XCTAssertFalse(feature.createTag)
        XCTAssertEqual(release.strategy, .mergeNoFastForward)
        XCTAssertFalse(release.createTag)
        XCTAssertEqual(hotfix.strategy, .mergeNoFastForward)
        XCTAssertTrue(hotfix.createTag)
    }

    func testRebaseFinishCreatesLinearDevelopHistoryAndDeletesSource() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createDivergedFeature(in: repositoryURL, conflicting: false)

        let originalSourceTip = try gitOutput(["rev-parse", "feature/linear"], in: repositoryURL)
        let originalDevelopTip = try gitOutput(["rev-parse", "develop"], in: repositoryURL)
        let result = try await GitFlowService().finish(
            topicPlan(source: "feature/linear", deleteSource: true),
            in: repositoryURL
        )

        let developTip = try gitOutput(["rev-parse", "develop"], in: repositoryURL)
        let parents = try gitOutput(["rev-list", "--parents", "-n", "1", "develop"], in: repositoryURL)
            .split(separator: " ")
        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertEqual(parents.count, 2)
        XCTAssertNotEqual(developTip, originalDevelopTip)
        XCTAssertNotEqual(result.rewrittenSourceTip, originalSourceTip)
        XCTAssertFalse(branches.contains("feature/linear"))
        XCTAssertEqual(result.targetResults.first?.tipBeforeMerge, originalDevelopTip)
    }

    func testRebaseConflictCanAbortToOriginalSourceTip() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createDivergedFeature(in: repositoryURL, conflicting: true)
        let originalSourceTip = try gitOutput(["rev-parse", "feature/linear"], in: repositoryURL)

        do {
            _ = try await GitFlowService().finish(
                topicPlan(source: "feature/linear", deleteSource: true),
                in: repositoryURL
            )
            XCTFail("Expected rebase conflict")
        } catch {
            let checkpoint = await GitFlowRecoveryStore().checkpoint(in: repositoryURL)
            XCTAssertEqual(checkpoint?.phase, .topicRebase)
            let rebaseInProgress = await GitStatusService.shared.isRebaseInProgress(in: repositoryURL)
            XCTAssertTrue(rebaseInProgress)
        }

        try await GitFlowService().abortFinish(in: repositoryURL)
        let rebaseInProgress = await GitStatusService.shared.isRebaseInProgress(in: repositoryURL)
        let checkpoint = await GitFlowRecoveryStore().checkpoint(in: repositoryURL)
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        XCTAssertFalse(rebaseInProgress)
        XCTAssertNil(checkpoint)
        XCTAssertEqual(try gitOutput(["rev-parse", "feature/linear"], in: repositoryURL), originalSourceTip)
        XCTAssertEqual(currentBranch, "feature/linear")
    }

    func testRebaseConflictResumeContinuesThenFastForwardsWithoutReplaying() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createDivergedFeature(in: repositoryURL, conflicting: true)

        do {
            _ = try await GitFlowService().finish(
                topicPlan(source: "feature/linear", deleteSource: false),
                in: repositoryURL
            )
            XCTFail("Expected rebase conflict")
        } catch {}

        try "resolved\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], in: repositoryURL)
        let result = try await GitFlowService().resumeFinish(in: repositoryURL)

        XCTAssertNotNil(result.rewrittenSourceTip)
        XCTAssertEqual(
            try gitOutput(["rev-parse", "develop"], in: repositoryURL),
            try gitOutput(["rev-parse", "feature/linear"], in: repositoryURL)
        )
        let checkpoint = await GitFlowRecoveryStore().checkpoint(in: repositoryURL)
        XCTAssertNil(checkpoint)
    }

    func testFastForwardCheckpointResumesFromRecordedRewrittenTip() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createDivergedFeature(in: repositoryURL, conflicting: false)
        let sourceTip = try gitOutput(["rev-parse", "feature/linear"], in: repositoryURL)
        let targetTip = try gitOutput(["rev-parse", "develop"], in: repositoryURL)
        try runGit(["rebase", "develop"], in: repositoryURL)
        let rewrittenTip = try gitOutput(["rev-parse", "feature/linear"], in: repositoryURL)
        let checkpoint = GitFlowFinishCheckpoint(
            plan: topicPlan(source: "feature/linear", deleteSource: false),
            sourceTip: sourceTip,
            targetResults: [],
            createdTagName: nil,
            phase: .topicFastForward,
            rewrittenSourceTip: rewrittenTip,
            targetTipBeforeIntegration: targetTip
        )
        try await GitFlowRecoveryStore().save(checkpoint, in: repositoryURL)

        let result = try await GitFlowService().resumeFinish(in: repositoryURL)

        XCTAssertEqual(result.rewrittenSourceTip, rewrittenTip)
        XCTAssertEqual(try gitOutput(["rev-parse", "develop"], in: repositoryURL), rewrittenTip)
    }

    func testRebaseUndoRedoOperationsRestoreRecordedTipsAndRefuseDrift() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createDivergedFeature(in: repositoryURL, conflicting: false)
        let result = try await GitFlowService().finish(
            topicPlan(source: "feature/linear", deleteSource: true),
            in: repositoryURL
        )
        let target = try XCTUnwrap(result.targetResults.first)
        let rewrittenTip = try XCTUnwrap(result.rewrittenSourceTip)
        let executor = GitUndoExecutor()

        try await executor.execute(
            .sequence([
                .requireCleanWorkingTree,
                .requireLocalBranchAbsent("feature/linear"),
                .checkoutRef(ref: "develop"),
                .resetHead(target: target.tipBeforeMerge, mode: .hard, expectedHead: target.tipAfterMerge),
                .createLocalBranch(name: "feature/linear", startPoint: result.sourceTip, checkout: true)
            ]),
            in: repositoryURL
        )
        XCTAssertEqual(try gitOutput(["rev-parse", "feature/linear"], in: repositoryURL), result.sourceTip)

        try await executor.execute(
            .sequence([
                .requireCleanWorkingTree,
                .requireLocalBranchTip(name: "feature/linear", expectedTip: result.sourceTip),
                .checkoutRef(ref: "develop"),
                .requireHead(target.tipBeforeMerge),
                .updateLocalBranch(name: "feature/linear", newTip: rewrittenTip, expectedTip: result.sourceTip),
                .mergeFastForward(branch: "feature/linear"),
                .deleteLocalBranch(name: "feature/linear", force: false, expectedTip: rewrittenTip)
            ]),
            in: repositoryURL
        )
        XCTAssertEqual(try gitOutput(["rev-parse", "develop"], in: repositoryURL), target.tipAfterMerge)

        try runGit(["commit", "--allow-empty", "-m", "drift"], in: repositoryURL)
        do {
            try await executor.execute(
                .resetHead(target: target.tipBeforeMerge, mode: .hard, expectedHead: target.tipAfterMerge),
                in: repositoryURL
            )
            XCTFail("Expected ref drift guard")
        } catch {
            XCTAssertNotNil(error as? GitUndoError)
        }
    }

    func testInvalidAndCollidingTagNamesFailBeforeMutation() async throws {
        let repositoryURL = try makeRepository()
        defer { try? FileManager.default.removeItem(at: repositoryURL) }
        try createRelease(in: repositoryURL)
        let originalMainTip = try gitOutput(["rev-parse", "main"], in: repositoryURL)
        let service = GitFlowService()

        let invalidError = await service.tagValidationError("bad tag", in: repositoryURL)
        XCTAssertEqual(invalidError, .invalidTagName("bad tag"))
        try runGit(["tag", "3.0.0", "main"], in: repositoryURL)
        let collisionError = await service.tagValidationError("3.0.0", in: repositoryURL)
        XCTAssertEqual(collisionError, .tagAlreadyExists("3.0.0"))
        XCTAssertEqual(try gitOutput(["rev-parse", "main"], in: repositoryURL), originalMainTip)
    }

    private func topicPlan(source: String, deleteSource: Bool) -> GitFlowFinishPlan {
        GitFlowFinishPlan(
            kind: .feature,
            sourceBranch: source,
            targetBranch: "develop",
            deleteSourceBranch: deleteSource,
            strategy: .rebaseFastForward
        )
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-git-flow-phase-5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
        try runGit(["config", "core.editor", "true"], in: repositoryURL)
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

    private func createDivergedFeature(in repositoryURL: URL, conflicting: Bool) throws {
        try runGit(["checkout", "develop"], in: repositoryURL)
        try runGit(["checkout", "-b", "feature/linear"], in: repositoryURL)
        let topicFile = conflicting ? "tracked.txt" : "feature.txt"
        try "feature\n".write(
            to: repositoryURL.appendingPathComponent(topicFile),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", topicFile], in: repositoryURL)
        try runGit(["commit", "-m", "feature"], in: repositoryURL)
        try runGit(["checkout", "develop"], in: repositoryURL)
        try "develop\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["commit", "-am", "develop"], in: repositoryURL)
        try runGit(["checkout", "feature/linear"], in: repositoryURL)
    }

    private func createRelease(in repositoryURL: URL) throws {
        try runGit(["checkout", "develop"], in: repositoryURL)
        try runGit(["checkout", "-b", "release/3.0.0"], in: repositoryURL)
        try runGit(["commit", "--allow-empty", "-m", "release"], in: repositoryURL)
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
