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
}

private struct GitCommandCall: Equatable {
    let arguments: [String]
    let directory: URL
}

private actor RecordingGitRunner: GitCommandRunning {
    private var calls: [GitCommandCall] = []

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls.append(GitCommandCall(arguments: arguments, directory: directory))
        return ""
    }

    func recordedCalls() -> [GitCommandCall] {
        calls
    }
}
