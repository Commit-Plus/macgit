import XCTest
@testable import macgit

final class GitDragDropBranchIntegrationTests: XCTestCase {
    func testMergeUndoResetsCurrentBranchToOldHead() async throws {
        let repoURL = try makeRepoWithDivergedBranches()
        let oldHead = try runGitOutput(["rev-parse", "main"], in: repoURL)
        let featureTip = try runGitOutput(["rev-parse", "feature"], in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.mergeCommit(commit: "feature", noCommit: false, log: false), in: repoURL)

        let mergedHead = try runGitOutput(["rev-parse", "main"], in: repoURL)
        XCTAssertNotEqual(mergedHead, oldHead)
        XCTAssertEqual(try runGitOutput(["rev-parse", "feature"], in: repoURL), featureTip)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature.txt").path))

        try await executor.execute(.resetHead(target: oldHead, mode: .hard, expectedHead: mergedHead), in: repoURL)

        XCTAssertEqual(try runGitOutput(["rev-parse", "HEAD"], in: repoURL), oldHead)
        XCTAssertEqual(try runGitOutput(["rev-parse", "feature"], in: repoURL), featureTip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature.txt").path))
    }

    func testRebaseUndoRestoresOldMainHead() async throws {
        let repoURL = try makeRepoWithDivergedBranches()
        let oldHead = try runGitOutput(["rev-parse", "main"], in: repoURL)
        let featureTip = try runGitOutput(["rev-parse", "feature"], in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.rebaseOnto(commit: "feature"), in: repoURL)

        let rebasedHead = try runGitOutput(["rev-parse", "main"], in: repoURL)
        XCTAssertNotEqual(rebasedHead, oldHead)
        XCTAssertEqual(try runGitOutput(["rev-parse", "feature"], in: repoURL), featureTip)
        XCTAssertEqual(try runGitStatus(["merge-base", "--is-ancestor", "feature", "main"], in: repoURL), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("main.txt").path))

        try await executor.execute(.resetHead(target: oldHead, mode: .hard, expectedHead: rebasedHead), in: repoURL)

        XCTAssertEqual(try runGitOutput(["rev-parse", "HEAD"], in: repoURL), oldHead)
        XCTAssertEqual(try runGitOutput(["rev-parse", "feature"], in: repoURL), featureTip)
    }

    private func makeRepoWithDivergedBranches() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-drag-drop-branch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)

        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)

        try runGit(["checkout", "-b", "feature"], in: repoURL)
        try "feature\n".write(to: repoURL.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "feature.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature"], in: repoURL)

        try runGit(["checkout", "main"], in: repoURL)
        try "main\n".write(to: repoURL.appendingPathComponent("main.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "main.txt"], in: repoURL)
        try runGit(["commit", "-m", "main"], in: repoURL)

        return repoURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        _ = try runGitOutput(arguments, in: repositoryURL)
    }

    private func runGitOutput(_ arguments: [String], in repositoryURL: URL) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw GitError.commandFailed(output)
        }
        return (String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGitStatus(_ arguments: [String], in repositoryURL: URL) throws -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }
}
