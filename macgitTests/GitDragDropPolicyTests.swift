import Foundation
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
