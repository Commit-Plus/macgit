import XCTest
@testable import macgit

final class GitUndoHistoryIntegrationTests: XCTestCase {
    func testCherryPickUndoResetsToOldHead() async throws {
        let repoURL = try makeRepoWithFeatureCommit()
        let oldHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        let featureHead = try runGitOutput(["rev-parse", "feature"], in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.cherryPick(commit: featureHead), in: repoURL)
        let newHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        try await executor.execute(.resetHead(target: oldHead, mode: .hard, expectedHead: newHead), in: repoURL)

        XCTAssertEqual(try runGitOutput(["rev-parse", "HEAD"], in: repoURL), oldHead)
    }

    func testBatchCherryPickRedoReappliesAllCommits() async throws {
        let repoURL = try makeRepoWithTwoFeatureCommits()
        let oldHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        let firstFeatureHead = try runGitOutput(["rev-parse", "feature~1"], in: repoURL)
        let secondFeatureHead = try runGitOutput(["rev-parse", "feature"], in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(
            .cherryPickCommits(commits: [firstFeatureHead, secondFeatureHead]),
            in: repoURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature-one.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature-two.txt").path))
        XCTAssertEqual(
            try runGitOutput(["log", "--format=%s", "-2"], in: repoURL)
                .components(separatedBy: "\n"),
            ["feature two", "feature one"]
        )

        let newHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        try await executor.execute(.resetHead(target: oldHead, mode: .hard, expectedHead: newHead), in: repoURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature-one.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature-two.txt").path))

        try await executor.execute(
            .cherryPickCommits(commits: [firstFeatureHead, secondFeatureHead]),
            in: repoURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature-one.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature-two.txt").path))
        XCTAssertEqual(
            try runGitOutput(["log", "--format=%s", "-2"], in: repoURL)
                .components(separatedBy: "\n"),
            ["feature two", "feature one"]
        )
    }

    func testCherryPickOntoNonCurrentBranchChecksOutTarget() async throws {
        let repoURL = try makeRepoWithTwoFeatureCommits()
        let mainHead = try runGitOutput(["rev-parse", "main"], in: repoURL)
        let featureHead = try runGitOutput(["rev-parse", "feature"], in: repoURL)
        let firstFeatureHead = try runGitOutput(["rev-parse", "feature~1"], in: repoURL)
        try runGit(["branch", "release"], in: repoURL)

        try await GitStatusService.shared.cherryPickCommits(
            [firstFeatureHead, featureHead],
            onto: "release",
            in: repoURL
        )

        XCTAssertEqual(try runGitOutput(["branch", "--show-current"], in: repoURL), "release")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature-one.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature-two.txt").path))
        XCTAssertEqual(try runGitOutput(["rev-parse", "main"], in: repoURL), mainHead)
        XCTAssertEqual(try runGitOutput(["rev-parse", "feature"], in: repoURL), featureHead)
    }

    func testRevertUndoResetsToOldHead() async throws {
        let repoURL = try makeTempRepo()
        try "changed\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "change tracked"], in: repoURL)

        let oldHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.revert(commit: oldHead), in: repoURL)
        let newHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        try await executor.execute(.resetHead(target: oldHead, mode: .hard, expectedHead: newHead), in: repoURL)

        XCTAssertEqual(try runGitOutput(["rev-parse", "HEAD"], in: repoURL), oldHead)
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("tracked.txt"), encoding: .utf8), "changed\n")
    }

    func testResetUndoRestoresOldHead() async throws {
        let repoURL = try makeTempRepo()
        try "second\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "second"], in: repoURL)

        let oldHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        let target = try runGitOutput(["rev-parse", "HEAD~1"], in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.resetHead(target: target, mode: .hard, expectedHead: oldHead), in: repoURL)
        try await executor.execute(.resetHead(target: oldHead, mode: .hard, expectedHead: target), in: repoURL)

        XCTAssertEqual(try runGitOutput(["rev-parse", "HEAD"], in: repoURL), oldHead)
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("tracked.txt"), encoding: .utf8), "second\n")
    }

    func testMergeUndoResetsToOldHead() async throws {
        let repoURL = try makeRepoWithFeatureCommit()
        let oldHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.mergeCommit(commit: "feature", noCommit: false, log: false), in: repoURL)
        let newHead = try runGitOutput(["rev-parse", "HEAD"], in: repoURL)
        try await executor.execute(.resetHead(target: oldHead, mode: .hard, expectedHead: newHead), in: repoURL)

        XCTAssertEqual(try runGitOutput(["rev-parse", "HEAD"], in: repoURL), oldHead)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("feature.txt").path))
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-undo-history-base-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)
        return repoURL
    }

    private func makeRepoWithFeatureCommit() throws -> URL {
        let repoURL = try makeTempRepo()
        try runGit(["checkout", "-b", "feature"], in: repoURL)
        try "feature\n".write(to: repoURL.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "feature.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature"], in: repoURL)
        try runGit(["checkout", "main"], in: repoURL)
        return repoURL
    }

    private func makeRepoWithTwoFeatureCommits() throws -> URL {
        let repoURL = try makeTempRepo()
        try runGit(["checkout", "-b", "feature"], in: repoURL)

        try "feature one\n".write(
            to: repoURL.appendingPathComponent("feature-one.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "feature-one.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature one"], in: repoURL)

        try "feature two\n".write(
            to: repoURL.appendingPathComponent("feature-two.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "feature-two.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature two"], in: repoURL)

        try runGit(["checkout", "main"], in: repoURL)
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
}
