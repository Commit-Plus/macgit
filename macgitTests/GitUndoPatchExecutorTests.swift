import XCTest
@testable import macgit

final class GitUndoPatchExecutorTests: XCTestCase {
    func testApplyPatchOperationUsesPatchRunnerFlags() async throws {
        let runner = RecordingGitRunner()
        let patchRunner = RecordingPatchRunner()
        let executor = GitUndoExecutor(runner: runner, patchRunner: patchRunner)
        let repoURL = URL(fileURLWithPath: "/tmp/repo")

        try await executor.execute(
            .applyPatch(patch: "patch text", cached: true, reverse: true),
            in: repoURL
        )

        let calls = await patchRunner.recordedCalls()
        XCTAssertEqual(calls, [
            PatchCall(patch: "patch text", directory: repoURL, cached: true, reverse: true)
        ])
        let commandCalls = await runner.recordedCalls()
        XCTAssertTrue(commandCalls.isEmpty)
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

private struct PatchCall: Equatable {
    let patch: String
    let directory: URL
    let cached: Bool
    let reverse: Bool
}

private actor RecordingPatchRunner: GitPatchApplying {
    private var calls: [PatchCall] = []

    func applyPatch(_ patch: String, in repositoryURL: URL, cached: Bool, reverse: Bool) async throws {
        calls.append(PatchCall(patch: patch, directory: repositoryURL, cached: cached, reverse: reverse))
    }

    func recordedCalls() -> [PatchCall] {
        calls
    }
}
