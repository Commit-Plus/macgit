import XCTest
@testable import macgit

@MainActor
final class GitUndoHunkIntegrationTests: XCTestCase {
    func testPatchOperationStagesAndUnstagesOneHunk() async throws {
        let repoURL = try makeTempRepo()
        let fileURL = repoURL.appendingPathComponent("tracked.txt")
        try "one\nchanged\nthree\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let status = try await GitStatusService.shared.status(for: repoURL)
        let file = try XCTUnwrap(status.unstaged.first { $0.path == "tracked.txt" })
        let hunks = try await GitStatusService.shared.diff(for: file, in: repoURL)
        let hunk = try XCTUnwrap(hunks.first)
        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: file.path)
        let executor = GitUndoExecutor()

        try await executor.execute(.applyPatch(patch: patch, cached: true, reverse: false), in: repoURL)
        var refreshed = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(refreshed.staged.contains { $0.path == "tracked.txt" })

        try await executor.execute(.applyPatch(patch: patch, cached: true, reverse: true), in: repoURL)
        refreshed = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertFalse(refreshed.staged.contains { $0.path == "tracked.txt" })
        XCTAssertTrue(refreshed.unstaged.contains { $0.path == "tracked.txt" })
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-undo-hunk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "one\ntwo\nthree\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)
        return repoURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = repositoryURL
        let stderr = Pipe()
        task.standardError = stderr
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let output = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(output)")
        }
    }
}
