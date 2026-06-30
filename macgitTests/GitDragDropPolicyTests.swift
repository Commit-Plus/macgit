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
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import macgit

final class GitDragDropPolicyTests: XCTestCase {
    func testDragPayloadLoadsFromItemProvider() async throws {
        let payload = GitDragPayload.commits(
            [GitDraggedCommit(hash: "c1", message: "commit", isMerge: false)],
            repositoryURL: repoURL
        )
        let provider = NSItemProvider()
        provider.register(payload)

        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.macgitGitDragPayload.identifier)
        )

        let loadedData: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.macgitGitDragPayload.identifier
            ) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "GitDragDropPolicyTests",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Missing drag payload data."]
                        )
                    )
                }
            }
        }

        XCTAssertEqual(try GitDragPayload.decodeTransferData(loadedData), payload)

        let loadedPayload: GitDragPayload = try await withCheckedThrowingContinuation { continuation in
            GitDragPayloadItemProviderLoader.load(from: provider) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertEqual(loadedPayload, payload)
    }

    func testDragPayloadLoadsFromRawDataItemProvider() async throws {
        let payload = GitDragPayload.branch("feature", repositoryURL: repoURL)
        let data = try GitDragPayload.encodeTransferData(payload)
        let provider = NSItemProvider(
            item: data as NSData,
            typeIdentifier: UTType.macgitGitDragPayload.identifier
        )

        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.macgitGitDragPayload.identifier)
        )

        let loadedPayload: GitDragPayload = try await withCheckedThrowingContinuation { continuation in
            GitDragPayloadItemProviderLoader.load(from: provider) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertEqual(loadedPayload, payload)
    }

    func testDragPayloadLoadsFromRegisteredDataRepresentation() async throws {
        let payload = GitDragPayload.branch("release", repositoryURL: repoURL)
        let data = try GitDragPayload.encodeTransferData(payload)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.macgitGitDragPayload.identifier,
            visibility: .all
        ) { completionHandler in
            completionHandler(data, nil)
            return nil
        }
        provider.register(payload)

        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.macgitGitDragPayload.identifier)
        )

        let loadedPayload: GitDragPayload = try await withCheckedThrowingContinuation { continuation in
            GitDragPayloadItemProviderLoader.load(from: provider) { result in
                continuation.resume(with: result)
            }
        }

        XCTAssertEqual(loadedPayload, payload)
    }

    func testRepositoryMismatchIsRejected() {
        let payload = GitDragPayload.commits(
            [GitDraggedCommit(hash: "c1", message: "commit", isMerge: false)],
            repositoryURL: URL(fileURLWithPath: "/tmp/source-repo")
        )

        XCTAssertEqual(
            GitDragDropPolicy.decision(
                for: payload,
                target: .localBranch(name: "main", isCurrent: true),
                receivingRepositoryURL: URL(fileURLWithPath: "/tmp/other-repo"),
                optionKeyPressed: false
            ),
            .reject("This drag item came from a different repository.")
        )
    }

    func testCommitsCanDropOnCurrentBranchInSameRepository() {
        let repoURL = URL(fileURLWithPath: "/tmp/repo")
        let payload = GitDragPayload.commits(
            [GitDraggedCommit(hash: "c2", message: "second", isMerge: false)],
            repositoryURL: repoURL
        )

        XCTAssertEqual(
            GitDragDropPolicy.decision(
                for: payload,
                target: .localBranch(name: "main", isCurrent: true),
                receivingRepositoryURL: repoURL,
                optionKeyPressed: false
            ),
            .accept(.cherryPick(commits: payload.commits, targetBranch: "main"))
        )
    }

    func testCommitsAreRejectedOnNonCurrentBranch() {
        let commit = GitDraggedCommit(hash: "c1", message: "commit", isMerge: false)

        XCTAssertEqual(
            decision(
                commits: [commit],
                target: .localBranch(name: "feature", isCurrent: false)
            ),
            .reject("Drop commits only on the current HEAD branch.")
        )
    }

    func testMergeCommitIsRejectedForCherryPick() {
        XCTAssertEqual(
            decision(
                commits: [GitDraggedCommit(hash: "merge", message: "merge", isMerge: true)]
            ),
            .reject("Merge commits are not supported by drag and drop yet.")
        )
    }

    func testSingleCommitCanCreateBranchFromBranchesHeader() {
        let commit = GitDraggedCommit(hash: "c3", message: "third", isMerge: false)

        XCTAssertEqual(
            decision(commits: [commit], target: .branchesHeader),
            .accept(.createBranch(startPoint: .commit(hash: "c3", message: "third")))
        )
    }

    func testMergeCommitCanCreateBranchFromBranchesHeader() {
        let commit = GitDraggedCommit(hash: "merge", message: "merge commit", isMerge: true)

        XCTAssertEqual(
            decision(commits: [commit], target: .branchesHeader),
            .accept(.createBranch(startPoint: .commit(hash: "merge", message: "merge commit")))
        )
    }

    func testMultipleCommitsAreRejectedForBranchCreation() {
        XCTAssertEqual(
            decision(
                commits: [
                    GitDraggedCommit(hash: "c1", message: "one", isMerge: false),
                    GitDraggedCommit(hash: "c2", message: "two", isMerge: false),
                ],
                target: .branchesHeader
            ),
            .reject("Select one commit to create a branch.")
        )
    }

    func testEmptyCommitBatchIsRejected() {
        XCTAssertEqual(
            decision(commits: []),
            .reject("Select at least one commit to drag.")
        )
    }

    func testUnsupportedCommitTargetCombinationIsRejected() {
        XCTAssertEqual(
            decision(
                commits: [GitDraggedCommit(hash: "c1", message: "one", isMerge: false)],
                target: .stashesHeader
            ),
            .reject("That drag and drop action is not available yet.")
        )
    }

    func testBranchCanMergeIntoCurrentBranch() {
        XCTAssertEqual(
            decision(
                payload: .branch("feature", repositoryURL: repoURL),
                target: .localBranch(name: "main", isCurrent: true)
            ),
            .accept(.branchOperation(source: "feature", target: "main", operation: .merge))
        )
    }

    func testBranchOptionDropCanRebaseCurrentBranch() {
        XCTAssertEqual(
            decision(
                payload: .branch("feature", repositoryURL: repoURL),
                target: .localBranch(name: "main", isCurrent: true),
                optionKeyPressed: true
            ),
            .accept(.branchOperation(source: "feature", target: "main", operation: .rebase))
        )
    }

    func testBranchSelfDropIsRejected() {
        XCTAssertEqual(
            decision(
                payload: .branch("main", repositoryURL: repoURL),
                target: .localBranch(name: "main", isCurrent: true)
            ),
            .reject("Drop a different branch onto the current branch.")
        )
    }

    func testBranchDropIsRejectedOnNonCurrentTarget() {
        XCTAssertEqual(
            decision(
                payload: .branch("feature", repositoryURL: repoURL),
                target: .localBranch(name: "release", isCurrent: false)
            ),
            .reject("Drop branches only on the current branch.")
        )
    }

    func testBranchCanCreateBranchFromBranchesHeader() {
        XCTAssertEqual(
            decision(
                payload: .branch("feature", repositoryURL: repoURL),
                target: .branchesHeader
            ),
            .accept(.createBranch(startPoint: .branch("feature")))
        )
    }

    private func decision(
        commits: [GitDraggedCommit],
        target: GitDragTarget = .localBranch(name: "main", isCurrent: true),
        repositoryURL: URL = URL(fileURLWithPath: "/tmp/repo")
    ) -> GitDragDropDecision {
        decision(
            payload: .commits(commits, repositoryURL: repositoryURL),
            target: target,
            receivingRepositoryURL: repositoryURL
        )
    }

    private func decision(
        payload: GitDragPayload,
        target: GitDragTarget,
        receivingRepositoryURL: URL? = nil,
        optionKeyPressed: Bool = false
    ) -> GitDragDropDecision {
        GitDragDropPolicy.decision(
            for: payload,
            target: target,
            receivingRepositoryURL: receivingRepositoryURL ?? repoURL,
            optionKeyPressed: optionKeyPressed
        )
    }

    private let repoURL = URL(fileURLWithPath: "/tmp/repo")
}
