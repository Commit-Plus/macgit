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

final class RepositoryAIRemoteOperationPolicyTests: XCTestCase {
    func testDecoderAcceptsOnlyOpaqueIDsAndTypedArity() throws {
        XCTAssertEqual(
            try RepositoryAIRemoteOperationProposalDecoder.decode(toolCall(
                name: "fetch_remote",
                arguments: ["remote-1"]
            )),
            .fetch(remoteID: "remote-1")
        )
        XCTAssertEqual(
            try RepositoryAIRemoteOperationProposalDecoder.decode(toolCall(
                name: "pull_fast_forward",
                arguments: ["remote-1", "current-upstream"]
            )),
            .pullFastForward(remoteID: "remote-1", branchID: "current-upstream")
        )

        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            try XCTUnwrap(RepositoryAIRemoteOperationProposalDecoder.decode(toolCall(
                name: "fetch_remote",
                arguments: ["https://example.com/owner/repository.git"]
            ))),
            context: makeContext()
        ))
        XCTAssertThrowsError(try RepositoryAIRemoteOperationProposalDecoder.decode(toolCall(
            name: "push_current_branch",
            arguments: ["remote-1", "--force"]
        )))
    }

    func testFetchUsesTrustedRemoteAndExactPreflightRequirements() throws {
        let validated = try RepositoryAIRemoteOperationPolicy.validate(
            .fetch(remoteID: "remote-1"),
            context: makeContext()
        )

        XCTAssertEqual(validated.expectedState.remote.name, "origin")
        XCTAssertEqual(validated.preview.confirmationLabel, "Fetch origin")
        XCTAssertTrue(validated.requirements.contains(.remoteIdentityUnchanged))
        XCTAssertTrue(validated.requirements.contains(.remoteTrackingRefUnchanged))
        XCTAssertFalse(validated.preview.summary.contains("https://"))
    }

    func testPullRequiresCleanAttachedFastForwardUpstream() throws {
        let valid = try RepositoryAIRemoteOperationPolicy.validate(
            .pullFastForward(remoteID: "remote-1", branchID: "current-upstream"),
            context: makeContext(ahead: 0, behind: 2)
        )
        XCTAssertEqual(valid.preview.confirmationLabel, "Pull origin/main")
        XCTAssertTrue(valid.requirements.contains(.fastForwardOnly))
        XCTAssertTrue(valid.preview.details.contains { $0.title == "Commits to pull" && $0.detail == "2" })

        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pullFastForward(remoteID: "remote-1", branchID: "current-upstream"),
            context: makeContext(isClean: false, ahead: 0, behind: 1)
        ))
        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pullFastForward(remoteID: "remote-1", branchID: "current-upstream"),
            context: makeContext(ahead: 1, behind: 1)
        ))
        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pullFastForward(remoteID: "remote-1", branchID: "current-upstream"),
            context: makeContext(branch: nil)
        ))
    }

    func testPushRequiresConfiguredNonDivergedUpstreamAndWarnsForProtectedBranch() throws {
        let valid = try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: "remote-1"),
            context: makeContext(ahead: 3, behind: 0, isProtected: true)
        )
        XCTAssertTrue(valid.requirements.contains(.ordinaryPushOnly))
        XCTAssertTrue(valid.preview.warning?.contains("default branch") == true)
        XCTAssertTrue(valid.preview.details.contains { $0.title == "Commits to push" && $0.detail == "3" })

        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: "remote-1"),
            context: makeContext(ahead: 1, behind: 1)
        ))
        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: "remote-2"),
            context: makeContext(ahead: 1, behind: 0)
        ))
        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: "remote-1"),
            context: makeContext(branch: nil)
        ))
    }

    func testChangedRemoteIdentityRefsOrWorkingStateMakesProposalStale() throws {
        let validated = try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: "remote-1"),
            context: makeContext(ahead: 1, behind: 0)
        )

        XCTAssertFalse(RepositoryAIRemoteOperationPolicy.isCurrent(
            validated,
            context: makeContext(identity: "remote-identity-2", ahead: 1, behind: 0)
        ))
        XCTAssertFalse(RepositoryAIRemoteOperationPolicy.isCurrent(
            validated,
            context: makeContext(trackingFingerprint: "tracking-2", ahead: 1, behind: 0)
        ))
        XCTAssertFalse(RepositoryAIRemoteOperationPolicy.isCurrent(
            validated,
            context: makeContext(workingFingerprint: "working-2", ahead: 1, behind: 0)
        ))
    }

    private func toolCall(name: String, arguments: [String]) -> RepositoryAIAgentToolCall {
        RepositoryAIAgentToolCall(id: "proposal", name: name, arguments: arguments)
    }

    private func makeContext(
        branch: String? = "main",
        identity: String = "remote-identity-1",
        trackingFingerprint: String = "tracking-1",
        workingFingerprint: String = "working-1",
        isClean: Bool = true,
        ahead: Int = 1,
        behind: Int = 0,
        isProtected: Bool = false
    ) -> RepositoryAIRemoteOperationPlanningContext {
        let state = RepositoryAIRepositoryState(
            branch: branch,
            head: String(repeating: "a", count: 40),
            stagedFingerprint: "index-1",
            workingTreeFingerprint: workingFingerprint
        )
        let remote = RepositoryAIRemoteManifest(
            id: "remote-1",
            name: "origin",
            identityFingerprint: identity,
            trackingRefsFingerprint: trackingFingerprint
        )
        let branchManifest = branch.map {
            RepositoryAIRemoteBranchManifest(
                id: "current-upstream",
                localBranch: $0,
                remoteID: remote.id,
                remoteBranch: "main",
                upstreamRef: "origin/main",
                localObjectID: state.head,
                remoteTrackingObjectID: String(repeating: "b", count: 40),
                commitsAhead: ahead,
                commitsBehind: behind,
                isProtected: isProtected
            )
        }
        return RepositoryAIRemoteOperationPlanningContext(
            repositoryIdentity: "/tmp/example",
            repositoryState: state,
            remotes: [remote],
            currentBranch: branchManifest,
            inProgressOperation: nil,
            isWorkingTreeClean: isClean
        )
    }
}
