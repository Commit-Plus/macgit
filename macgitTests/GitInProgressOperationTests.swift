import XCTest
@testable import macgit

final class GitInProgressOperationTests: XCTestCase {
    func testCherryPickConflictLeavesInProgressState() async throws {
        let repoURL = try makeConflictingRepo()
        let featureHead = try runGitOutput(["rev-parse", "feature"], in: repoURL)

        do {
            try await GitStatusService.shared.cherryPickCommit(featureHead, in: repoURL)
            XCTFail("cherry-pick should conflict")
        } catch {
            // expected
        }

        let operation = await GitStatusService.shared.inProgressOperation(in: repoURL)
        XCTAssertEqual(operation, .cherryPick(head: featureHead))

        try await GitStatusService.shared.abortCherryPick(in: repoURL)
        let afterAbort = await GitStatusService.shared.inProgressOperation(in: repoURL)
        XCTAssertNil(afterAbort)
    }

    func testRevertConflictLeavesInProgressState() async throws {
        let repoURL = try makeTempRepo()
        try "first\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "first"], in: repoURL)

        try "second\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "second"], in: repoURL)

        let firstCommit = try runGitOutput(["rev-parse", "HEAD~1"], in: repoURL)

        do {
            try await GitStatusService.shared.revertCommit(firstCommit, in: repoURL)
            XCTFail("revert should conflict")
        } catch {
            // expected
        }

        let operation = await GitStatusService.shared.inProgressOperation(in: repoURL)
        XCTAssertEqual(operation, .revert(head: firstCommit))

        try await GitStatusService.shared.abortRevert(in: repoURL)
        let afterAbort = await GitStatusService.shared.inProgressOperation(in: repoURL)
        XCTAssertNil(afterAbort)
    }

    func testEmptyCherryPickLeavesInProgressStateWithoutConflicts() async throws {
        let repoURL = try makeEmptyCherryPickRepo()
        let featureHead = try runGitOutput(["rev-parse", "feature"], in: repoURL)

        do {
            try await GitStatusService.shared.cherryPickCommit(featureHead, in: repoURL)
            XCTFail("cherry-pick should be empty and fail")
        } catch {
            // expected
        }

        let operation = await GitStatusService.shared.inProgressOperation(in: repoURL)
        XCTAssertEqual(operation, .cherryPick(head: featureHead))

        let hasConflicts = await GitStatusService.shared.hasConflicts(in: repoURL)
        XCTAssertFalse(hasConflicts, "Empty cherry-pick should not produce conflicts")

        try await GitStatusService.shared.abortCherryPick(in: repoURL)
        let afterAbort = await GitStatusService.shared.inProgressOperation(in: repoURL)
        XCTAssertNil(afterAbort)
    }

    func testSkipCherryPickClearsEmptyInProgressState() async throws {
        let repoURL = try makeEmptyCherryPickRepo()
        let featureHead = try runGitOutput(["rev-parse", "feature"], in: repoURL)

        do {
            try await GitStatusService.shared.cherryPickCommit(featureHead, in: repoURL)
            XCTFail("cherry-pick should be empty and fail")
        } catch {
            // expected
        }

        let operation = await GitStatusService.shared.inProgressOperation(in: repoURL)
        XCTAssertEqual(operation, .cherryPick(head: featureHead))

        try await GitStatusService.shared.skipCherryPick(in: repoURL)
        let afterSkip = await GitStatusService.shared.inProgressOperation(in: repoURL)
        XCTAssertNil(afterSkip, "skip should clear the in-progress cherry-pick state")
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-in-progress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)
        return repoURL
    }

    private func makeConflictingRepo() throws -> URL {
        let repoURL = try makeTempRepo()
        try runGit(["checkout", "-b", "feature"], in: repoURL)
        try "feature\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature"], in: repoURL)

        try runGit(["checkout", "main"], in: repoURL)
        try "main\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "main"], in: repoURL)
        return repoURL
    }

    private func makeEmptyCherryPickRepo() throws -> URL {
        let repoURL = try makeTempRepo()
        try runGit(["checkout", "-b", "feature"], in: repoURL)
        try "feature\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "feature"], in: repoURL)
        try runGit(["checkout", "main"], in: repoURL)
        // Bring feature's changes into main via merge so cherry-picking feature again is empty.
        try runGit(["merge", "--no-ff", "feature", "-m", "merge feature"], in: repoURL)
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
