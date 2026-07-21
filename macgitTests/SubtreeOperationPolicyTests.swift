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

final class SubtreeOperationPolicyTests: XCTestCase {
    func testSupportsGitSubtreeAcceptsHelpOutputEvenWhenGitReturnsUsageFailure() async throws {
        let runner = RecordingSubtreePolicyRunner(failures: [
            "subtree -h": GitError.commandFailed("usage: git subtree add --prefix=<prefix> <repository> <ref>")
        ])
        let service = GitStatusService(runner: runner)

        let isSupported = await service.supportsGitSubtree(in: URL(fileURLWithPath: "/tmp/repo"))
        let calls = await runner.recordedArguments()

        XCTAssertTrue(isSupported)
        XCTAssertEqual(calls, [["subtree", "-h"]])
    }

    func testSupportsGitSubtreeRejectsMissingCommand() async throws {
        let runner = RecordingSubtreePolicyRunner(failures: [
            "subtree -h": GitError.commandFailed("git: 'subtree' is not a git command")
        ])
        let service = GitStatusService(runner: runner)

        let isSupported = await service.supportsGitSubtree(in: URL(fileURLWithPath: "/tmp/repo"))

        XCTAssertFalse(isSupported)
    }

    func testCleanParentAllowsSubtreeOperation() async throws {
        let runner = RecordingSubtreePolicyRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": ""
        ])
        let service = GitStatusService(runner: runner)

        let decision = try await service.subtreeOperationDecision(in: URL(fileURLWithPath: "/tmp/repo"))

        XCTAssertEqual(
            decision,
            SubtreeOperationDecision(isAllowed: true, blockingPaths: [], message: nil)
        )
    }

    func testDecisionBlocksWhenGitSubtreeIsUnavailable() async throws {
        let runner = RecordingSubtreePolicyRunner(failures: [
            "subtree -h": GitError.commandFailed("git: 'subtree' is not a git command")
        ])
        let service = GitStatusService(runner: runner)

        let decision = try await service.subtreeOperationDecision(in: URL(fileURLWithPath: "/tmp/repo"))

        XCTAssertEqual(
            decision,
            SubtreeOperationDecision(
                isAllowed: false,
                blockingPaths: [],
                message: "This Git installation does not include git subtree."
            )
        )
        let calls = await runner.recordedArguments()
        XCTAssertEqual(calls, [["subtree", "-h"]])
    }

    func testDirtyParentBlocksStagedModifiedUntrackedAndConflictRecords() async throws {
        let status = [
            "M  staged.txt",
            " M modified.txt",
            "?? untracked.txt",
            "UU conflict.txt"
        ].joined(separator: "\0") + "\0"
        let runner = RecordingSubtreePolicyRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": status
        ])
        let service = GitStatusService(runner: runner)

        let decision = try await service.subtreeOperationDecision(in: URL(fileURLWithPath: "/tmp/repo"))

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.blockingPaths, ["conflict.txt", "modified.txt", "staged.txt", "untracked.txt"])
        XCTAssertEqual(decision.message, "Commit, stash, or discard changes before running subtree operations.")
    }

    func testDirtyParentHandlesRenameRecordsAndSortsDeterministically() async throws {
        let status = [
            "R  old-name.txt\0new-name.txt",
            " M zeta.txt",
            "A  alpha.txt"
        ].joined(separator: "\0") + "\0"
        let runner = RecordingSubtreePolicyRunner(outputs: [
            "subtree -h": "usage: git subtree add --prefix=<prefix> <repository> <ref>",
            "status --porcelain=v1 -z": status
        ])
        let service = GitStatusService(runner: runner)

        let decision = try await service.subtreeOperationDecision(in: URL(fileURLWithPath: "/tmp/repo"))

        XCTAssertEqual(decision.blockingPaths, ["alpha.txt", "new-name.txt", "zeta.txt"])
    }
}

private actor RecordingSubtreePolicyRunner: GitCommandRunning {
    private let outputs: [String: String]
    private let failures: [String: Error]
    private var calls: [[String]] = []

    init(outputs: [String: String] = [:], failures: [String: Error] = [:]) {
        self.outputs = outputs
        self.failures = failures
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls.append(arguments)
        let key = arguments.joined(separator: " ")
        if let failure = failures[key] {
            throw failure
        }
        return outputs[key] ?? ""
    }

    func recordedArguments() -> [[String]] {
        calls
    }
}
