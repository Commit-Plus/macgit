import XCTest
@testable import macgit

final class GitUndoExecutorTests: XCTestCase {
    func testStageFilesRunsGitAddWithPathspecSeparator() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.stageFiles(paths: ["README.md", "Sources/App.swift"]), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: ["add", "--", "README.md", "Sources/App.swift"],
                directory: repoURL
            )
        ])
    }

    func testUnstageFilesRunsGitResetHeadWithPathspecSeparator() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.unstageFiles(paths: ["README.md"]), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: ["reset", "HEAD", "--", "README.md"],
                directory: repoURL
            )
        ])
    }

    func testEmptyPathListThrowsBeforeRunningGit() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        do {
            try await executor.execute(.stageFiles(paths: []), in: repoURL)
            XCTFail("Expected emptyPathList error")
        } catch let error as GitUndoError {
            XCTAssertEqual(error, .emptyPathList)
        }

        let calls = await runner.recordedCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testCheckoutRefRunsGitCheckout() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.checkoutRef(ref: "feature"), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["checkout", "feature"], directory: repoURL)
        ])
    }

    func testCreateLocalBranchUsesBranchCommandWhenCheckoutDisabled() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .createLocalBranch(name: "feature", startPoint: "abc123", checkout: false),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["branch", "feature", "abc123"], directory: repoURL)
        ])
    }

    func testDeleteLocalBranchChecksExpectedTipBeforeDeleting() async throws {
        let runner = RecordingGitRunner(outputs: ["rev-parse feature^{commit}": "abc123\n"])
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .deleteLocalBranch(name: "feature", force: true, expectedTip: "abc123"),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["rev-parse", "feature^{commit}"], directory: repoURL),
            GitCommandCall(arguments: ["branch", "-D", "feature"], directory: repoURL)
        ])
    }

    func testSetUpstreamRunsGitBranchSetUpstreamTo() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .setUpstream(branch: "feature", upstream: "origin/feature"),
            in: repoURL
        )

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(
                arguments: ["branch", "--set-upstream-to", "origin/feature", "feature"],
                directory: repoURL
            )
        ])
    }

    func testRevertRunsGitRevert() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.revert(commit: "abc123"), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["revert", "--no-edit", "abc123"], directory: repoURL)
        ])
    }

    func testMergeCommitRunsGitMergeWithSelectedFlags() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.mergeCommit(commit: "feature", noCommit: true, log: true), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["merge", "--no-commit", "--log", "feature"], directory: repoURL)
        ])
    }

    func testRebaseOntoRunsGitRebase() async throws {
        let runner = RecordingGitRunner()
        let executor = GitUndoExecutor(runner: runner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(.rebaseOnto(commit: "origin/main"), in: repoURL)

        let calls = await runner.recordedCalls()
        XCTAssertEqual(calls, [
            GitCommandCall(arguments: ["rebase", "origin/main"], directory: repoURL)
        ])
    }
}

private struct GitCommandCall: Equatable {
    let arguments: [String]
    let directory: URL
}

private actor RecordingGitRunner: GitCommandRunning {
    private let outputs: [String: String]
    private var calls: [GitCommandCall] = []

    init(outputs: [String: String] = [:]) {
        self.outputs = outputs
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls.append(GitCommandCall(arguments: arguments, directory: directory))
        return outputs[arguments.joined(separator: " ")] ?? ""
    }

    func recordedCalls() -> [GitCommandCall] {
        calls
    }
}
