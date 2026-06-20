import XCTest
@testable import macgit

final class GitUndoBranchIntegrationTests: XCTestCase {
    func testUndoCreateBranchDeletesCreatedBranchWhenTipMatches() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)
        let branchesAfterCreate = await GitStatusService.shared.localBranches(in: repoURL)
        XCTAssertTrue(branchesAfterCreate.contains("feature"))

        try await executor.execute(.deleteLocalBranch(name: "feature", force: true, expectedTip: start), in: repoURL)
        let branchesAfterDelete = await GitStatusService.shared.localBranches(in: repoURL)
        XCTAssertFalse(branchesAfterDelete.contains("feature"))
    }

    func testUndoDeleteBranchRecreatesBranchAtCapturedTip() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)
        try await executor.execute(.deleteLocalBranch(name: "feature", force: true, expectedTip: start), in: repoURL)
        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)

        let restoredTip = try await support.tip(of: "feature", in: repoURL)
        XCTAssertEqual(restoredTip, start)
    }

    func testCheckoutRefSwitchesCurrentBranch() async throws {
        let repoURL = try makeTempRepo()
        let support = GitBranchUndoSupport()
        let start = try await support.tip(of: "main", in: repoURL)
        let executor = GitUndoExecutor()

        try await executor.execute(.createLocalBranch(name: "feature", startPoint: start, checkout: false), in: repoURL)
        try await executor.execute(.checkoutRef(ref: "feature"), in: repoURL)

        let currentRef = try await support.currentRef(in: repoURL)
        XCTAssertEqual(currentRef, "feature")
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-undo-branch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
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
            throw GitError.commandFailed(output)
        }
    }
}
