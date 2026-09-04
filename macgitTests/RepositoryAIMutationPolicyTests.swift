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

final class RepositoryAIMutationPolicyTests: XCTestCase {
    func testDecoderResolvesOnlyOpaqueEligiblePathIDs() throws {
        let context = makeContext()
        let response = try RepositoryAIMutationProposalDecoder.decode(
            toolCall: RepositoryAIAgentToolCall(
                id: "proposal",
                name: "stage_files",
                arguments: ["unstaged-1", "untracked-1"]
            ),
            context: context
        )

        guard case .proposal(.stageFiles(let paths)) = response else {
            return XCTFail("Expected a stage proposal")
        }
        XCTAssertEqual(paths.map(\.file.path), ["App.swift", "New.swift"])

        XCTAssertThrowsError(try RepositoryAIMutationProposalDecoder.decode(
            toolCall: RepositoryAIAgentToolCall(
                id: "raw-path",
                name: "stage_files",
                arguments: ["App.swift"]
            ),
            context: context
        ))
        XCTAssertThrowsError(try RepositoryAIMutationProposalDecoder.decode(
            toolCall: RepositoryAIAgentToolCall(
                id: "wildcard",
                name: "stage_files",
                arguments: ["*"]
            ),
            context: context
        ))
    }

    func testDecoderRejectsUnknownActionsAndExtraDestructiveFields() {
        let context = makeContext()
        XCTAssertThrowsError(try RepositoryAIMutationProposalDecoder.decode(
            toolCall: RepositoryAIAgentToolCall(
                id: "raw-command",
                name: "run_command",
                arguments: ["git", "reset", "--hard"]
            ),
            context: context
        ))
        XCTAssertThrowsError(try RepositoryAIMutationProposalDecoder.decode(
            toolCall: RepositoryAIAgentToolCall(
                id: "amend",
                name: "create_commit",
                arguments: ["feat: safe", "--amend"]
            ),
            context: context
        ))
        XCTAssertThrowsError(try RepositoryAIMutationProposalDecoder.decode(
            toolCall: RepositoryAIAgentToolCall(
                id: "unknown-ref",
                name: "checkout_branch",
                arguments: ["feature"]
            ),
            context: context
        ))
    }

    func testStructuredToolPayloadRejectsUnexpectedFields() throws {
        let valid = try JSONDecoder().decode(
            RepositoryAIAgentToolArgumentsPayload.self,
            from: Data(#"{"arguments":["feat: safe"]}"#.utf8)
        )
        XCTAssertEqual(valid.arguments, ["feat: safe"])

        XCTAssertThrowsError(try JSONDecoder().decode(
            RepositoryAIAgentToolArgumentsPayload.self,
            from: Data(#"{"arguments":["feat: unsafe"],"amend":true}"#.utf8)
        ))
    }

    func testCommitAllWorkflowRequiresNoArgumentsAndACompleteSafeManifest() throws {
        let context = makeContext()
        let response = try RepositoryAIMutationProposalDecoder.decode(
            toolCall: RepositoryAIAgentToolCall(
                id: "commit-all",
                name: "commit_all_changes",
                arguments: []
            ),
            context: context
        )
        XCTAssertEqual(response, .workflow(.commitAllChanges))

        XCTAssertThrowsError(try RepositoryAIMutationProposalDecoder.decode(
            toolCall: RepositoryAIAgentToolCall(
                id: "commit-all-with-arguments",
                name: "commit_all_changes",
                arguments: ["--all"]
            ),
            context: context
        ))

        let stageMutation = try RepositoryAIMutationPolicy.validateCommitAllPreparation(
            context: context
        )
        guard case .stageFiles(let paths) = stageMutation.proposal else {
            return XCTFail("Expected exact stage-files preparation")
        }
        XCTAssertEqual(Set(paths.map(\.file.path)), ["App.swift", "New.swift"])

        let conflict = StatusFile(path: "Conflict.swift", status: .conflict, originalPath: nil)
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validateCommitAllPreparation(
            context: makeContext(status: GitStatus(staged: [], unstaged: [conflict], untracked: []))
        ))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validateCommitAllPreparation(
            context: makeContext(branch: nil)
        ))
    }

    func testStagePreservesDuplicatePathSourcesAndRenamePair() throws {
        let context = makeContext()
        let staged = try RepositoryAIMutationPolicy.validate(
            .stageFiles(paths: [try XCTUnwrap(context.path(id: "unstaged-1"))]),
            context: context
        )
        guard case .stageFiles(let paths) = staged.proposal else {
            return XCTFail("Expected stage files")
        }
        XCTAssertEqual(paths.single?.source, .unstaged)
        XCTAssertEqual(paths.single?.file.path, "App.swift")
        XCTAssertTrue(context.paths.contains { $0.source == .staged && $0.file.path == "App.swift" })

        let renameContext = makeContext(
            status: GitStatus(
                staged: [],
                unstaged: [StatusFile(path: "Sources/New.swift", status: .renamed, originalPath: "Sources/Old.swift")],
                untracked: []
            )
        )
        let rename = try RepositoryAIMutationPolicy.validate(
            .stageFiles(paths: [try XCTUnwrap(renameContext.path(id: "unstaged-1"))]),
            context: renameContext
        )
        XCTAssertTrue(rename.preview.items[0].detail.contains("Sources/Old.swift"))
    }

    func testCommitRequiresMessageIndexIdentityAndAttachedHead() throws {
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .createCommit(message: "  feat: padded  "),
            context: makeContext()
        ))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .createCommit(message: "feat: valid"),
            context: makeContext(author: nil)
        ))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .createCommit(message: "feat: valid"),
            context: makeContext(branch: nil)
        ))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .createCommit(message: "feat: valid"),
            context: makeContext(status: GitStatus(staged: [], unstaged: [], untracked: []))
        ))

        let validated = try RepositoryAIMutationPolicy.validate(
            .createCommit(message: "feat: valid"),
            context: makeContext(signingEnabled: true)
        )
        XCTAssertTrue(validated.preview.details.contains { $0.title == "Signing" && $0.detail.contains("Enabled") })
    }

    func testCheckoutRejectsDirtySequencerCurrentAndOtherWorktreeBranch() throws {
        let target = try XCTUnwrap(makeContext().localBranch(id: "branch-2"))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .checkoutBranch(target: target),
            context: makeContext()
        ))

        let clean = GitStatus(staged: [], unstaged: [], untracked: [])
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .checkoutBranch(target: target),
            context: makeContext(status: clean, inProgressOperation: "Cherry-pick")
        ))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .checkoutBranch(target: target),
            context: makeContext(status: clean, otherWorktreeBranches: ["feature"])
        ))

        let current = try XCTUnwrap(makeContext(status: clean).localBranch(id: "branch-1"))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .checkoutBranch(target: current),
            context: makeContext(status: clean)
        ))
    }

    func testCreateBranchRejectsExistingInvalidAndUnknownStartPoint() throws {
        let context = makeContext()
        let start = try XCTUnwrap(context.startPoint(id: "start-head"))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .createBranch(name: "main", startPoint: start),
            context: context
        ))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .createBranch(name: "feature --force", startPoint: start),
            context: context
        ))
        XCTAssertThrowsError(try RepositoryAIMutationPolicy.validate(
            .createBranch(
                name: "safe-branch",
                startPoint: RepositoryAIMutationRef(id: "invented", name: "HEAD~1", commit: "bad")
            ),
            context: context
        ))
    }

    func testFingerprintChangeMakesValidatedProposalStale() throws {
        let context = makeContext()
        let validated = try RepositoryAIMutationPolicy.validate(
            .stageFiles(paths: [try XCTUnwrap(context.path(id: "unstaged-1"))]),
            context: context
        )
        let changed = makeContext(stagedFingerprint: "index-2")

        XCTAssertFalse(RepositoryAIMutationPolicy.isCurrent(
            validated.precondition,
            proposal: validated.proposal,
            context: changed
        ))
    }

    private func makeContext(
        status: GitStatus? = nil,
        branch: String? = "main",
        stagedFingerprint: String = "index-1",
        author: String? = "Test User <test@example.com>",
        signingEnabled: Bool = false,
        inProgressOperation: String? = nil,
        otherWorktreeBranches: Set<String> = []
    ) -> RepositoryAIMutationPlanningContext {
        let resolvedStatus = status ?? GitStatus(
            staged: [StatusFile(path: "App.swift", status: .staged, originalPath: nil)],
            unstaged: [StatusFile(path: "App.swift", status: .modified, originalPath: nil)],
            untracked: [StatusFile(path: "New.swift", status: .untracked, originalPath: nil)]
        )
        let state = RepositoryAIRepositoryState(
            branch: branch,
            head: String(repeating: "a", count: 40),
            stagedFingerprint: stagedFingerprint,
            workingTreeFingerprint: "worktree-1"
        )
        let paths = resolvedStatus.staged.enumerated().map { index, file in
            RepositoryAIMutationPath(id: "staged-\(index + 1)", file: file, source: file.status == .conflict ? .conflict : .staged)
        } + resolvedStatus.unstaged.enumerated().map { index, file in
            RepositoryAIMutationPath(id: "unstaged-\(index + 1)", file: file, source: file.status == .conflict ? .conflict : .unstaged)
        } + resolvedStatus.untracked.enumerated().map { index, file in
            RepositoryAIMutationPath(id: "untracked-\(index + 1)", file: file, source: .untracked)
        }
        let branches = [
            RepositoryAIMutationRef(id: "branch-1", name: "main", commit: state.head),
            RepositoryAIMutationRef(id: "branch-2", name: "feature", commit: String(repeating: "b", count: 40)),
        ]
        return RepositoryAIMutationPlanningContext(
            repositoryIdentity: "/tmp/example",
            repositoryState: state,
            status: resolvedStatus,
            paths: paths,
            localBranches: branches,
            startPoints: [RepositoryAIMutationRef(id: "start-head", name: "HEAD", commit: state.head)],
            conflictResolutions: [],
            stagedStatistics: RepositoryAIMutationStatistics(
                fileCount: resolvedStatus.staged.count,
                additions: 4,
                deletions: 2,
                binaryFileCount: 0
            ),
            author: author,
            signingEnabled: signingEnabled,
            inProgressOperation: inProgressOperation,
            branchesCheckedOutInOtherWorktrees: otherWorktreeBranches
        )
    }
}

private extension Array {
    var single: Element? { count == 1 ? self[0] : nil }
}
