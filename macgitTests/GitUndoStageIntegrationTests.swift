import XCTest
@testable import macgit

final class GitUndoStageIntegrationTests: XCTestCase {
    func testExecutorStagesAndUnstagesTrackedFileInRealRepo() async throws {
        let repoURL = try makeTempRepo()
        let fileURL = repoURL.appendingPathComponent("tracked.txt")
        try "changed\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let executor = GitUndoExecutor()
        try await executor.execute(.stageFiles(paths: ["tracked.txt"]), in: repoURL)

        var status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(status.staged.contains { $0.path == "tracked.txt" })
        XCTAssertFalse(status.unstaged.contains { $0.path == "tracked.txt" })

        try await executor.execute(.unstageFiles(paths: ["tracked.txt"]), in: repoURL)

        status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertFalse(status.staged.contains { $0.path == "tracked.txt" })
        XCTAssertTrue(status.unstaged.contains { $0.path == "tracked.txt" })
    }

    func testExecutorStagesAndUnstagesUntrackedFileInRealRepo() async throws {
        let repoURL = try makeTempRepo()
        let fileURL = repoURL.appendingPathComponent("new.txt")
        try "new file\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let executor = GitUndoExecutor()
        try await executor.execute(.stageFiles(paths: ["new.txt"]), in: repoURL)

        var status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(status.staged.contains { $0.path == "new.txt" })
        XCTAssertFalse(status.untracked.contains { $0.path == "new.txt" })

        try await executor.execute(.unstageFiles(paths: ["new.txt"]), in: repoURL)

        status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertFalse(status.staged.contains { $0.path == "new.txt" })
        XCTAssertTrue(status.untracked.contains { $0.path == "new.txt" })
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-undo-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)

        let trackedFile = repoURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial commit"], in: repoURL)

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
            let outputData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "git failed"
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(output)")
        }
    }
}
