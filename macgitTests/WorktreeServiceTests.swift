import XCTest
@testable import macgit

final class WorktreeServiceTests: XCTestCase {
    func testWorktreesWithLabelsMergesStoredLabels() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        try runGit(["worktree", "add", wtPath.path, "feature"], in: repoURL)
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)
        try WorktreeLabelStore().setLabel("Review UI", for: wtPath, in: gitDirectory)

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repoURL)

        XCTAssertEqual(entries.first(where: { $0.path.path == wtPath.path })?.label, "Review UI")
        XCTAssertEqual(entries.first(where: { $0.path.path == wtPath.path })?.displayTitle, "Review UI")
    }

    func testWorktreesWithLabelsPrunesOrphanedLabels() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        let orphanPath = repoURL.deletingLastPathComponent().appendingPathComponent("orphan-\(UUID().uuidString)")
        try runGit(["worktree", "add", wtPath.path, "feature"], in: repoURL)
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)
        let store = WorktreeLabelStore()
        try store.setLabel("Review UI", for: wtPath, in: gitDirectory)
        try store.setLabel("Remove", for: orphanPath, in: gitDirectory)

        _ = await GitStatusService.shared.worktreesWithLabels(in: repoURL)

        XCTAssertNil(store.label(for: orphanPath, in: gitDirectory))
        XCTAssertEqual(store.label(for: wtPath, in: gitDirectory), "Review UI")
    }

    func testAddWorktreeCreatesExistingBranchWorktreeAndPersistsLabel() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")

        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: "Review UI",
            in: repoURL
        )

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repoURL)
        let added = entries.first(where: { $0.path.path == wtPath.path })
        XCTAssertEqual(added?.branch, "feature")
        XCTAssertEqual(added?.label, "Review UI")
    }

    func testAddWorktreeCreatesNewBranchFromBase() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/release-hotfix")
        let base = try runGitCapture(["rev-parse", "main"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines)

        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .newBranch(name: "release/hotfix", base: base),
            label: nil,
            in: repoURL
        )

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        XCTAssertEqual(entries.first(where: { $0.path.path == wtPath.path })?.branch, "release/hotfix")
    }

    func testRemoveWorktreeDeletesLabelAndWorktree() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: "Review UI",
            in: repoURL
        )

        try await GitStatusService.shared.removeWorktree(at: wtPath, force: false, in: repoURL)

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repoURL)
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)
        XCTAssertNil(entries.first(where: { $0.path.path == wtPath.path }))
        XCTAssertNil(WorktreeLabelStore().label(for: wtPath, in: gitDirectory))
    }

    func testRemoveDirtyWorktreeRequiresForce() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: nil,
            in: repoURL
        )
        try "dirty\n".write(to: wtPath.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        do {
            try await GitStatusService.shared.removeWorktree(at: wtPath, force: false, in: repoURL)
            XCTFail("Expected removeWorktree to fail for dirty worktree without force")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testRemoveDirtyWorktreeWithForceDeletesWorktreeAndLabel() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: "Review UI",
            in: repoURL
        )
        try "dirty\n".write(to: wtPath.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        try await GitStatusService.shared.removeWorktree(at: wtPath, force: true, in: repoURL)

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repoURL)
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)
        XCTAssertNil(entries.first(where: { $0.path.path == wtPath.path }))
        XCTAssertNil(WorktreeLabelStore().label(for: wtPath, in: gitDirectory))
    }

    func testRemoveMainWorktreeFailsBeforeRunningGit() async throws {
        let repoURL = try makeTempRepo()

        do {
            try await GitStatusService.shared.removeWorktree(at: repoURL, force: true, in: repoURL)
            XCTFail("Expected removeWorktree to reject removing the main worktree")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("main"))
        }

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.path.path, repoURL.path)
    }

    func testSetWorktreeLabelPostsRepositoryDidChange() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: nil,
            in: repoURL
        )
        let expectation = expectation(forNotification: .repositoryDidChange, object: nil) { notification in
            (notification.userInfo?["repositoryURL"] as? URL)?.path == repoURL.path
        }

        try await GitStatusService.shared.setWorktreeLabel("Agent task", for: wtPath, in: repoURL)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testListsOnlyMainWorktree() async throws {
        let repoURL = try makeTempRepo()

        let entries = await GitStatusService.shared.worktrees(in: repoURL)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].path.path, repoURL.path)
        XCTAssertFalse(entries[0].isLocked)
        XCTAssertNotNil(entries[0].branch)
        XCTAssertEqual(entries[0].dirtyCount, 0)
    }

    func testListsMultipleWorktreesAndParsesBranch() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        try runGit(["worktree", "add", wtPath.path, "feature"], in: repoURL)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)

        XCTAssertEqual(entries.count, 2)
        let main = entries.first(where: { $0.path.path == repoURL.path })
        let linked = entries.first(where: { $0.path.path == wtPath.path })
        XCTAssertNotNil(main)
        XCTAssertEqual(linked?.branch, "feature")
        XCTAssertFalse(linked?.isLocked ?? true)
    }

    func testParsesLockedWorktree() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        try runGit(["worktree", "add", wtPath.path, "feature"], in: repoURL)
        try runGit(["worktree", "lock", wtPath.path], in: repoURL)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)

        XCTAssertEqual(entries.first(where: { $0.path.path == wtPath.path })?.isLocked, true)
    }

    func testParsesDetachedHeadWorktree() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        let head = try runGitCapture(["rev-parse", "HEAD"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["worktree", "add", "--detach", wtPath.path, head], in: repoURL)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)

        let linked = entries.first(where: { $0.path.path == wtPath.path })
        XCTAssertNil(linked?.branch)
        XCTAssertFalse(linked?.head.isEmpty ?? true)
    }

    func testDirtyCountReflectsWorktreeStatus() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.deletingLastPathComponent().appendingPathComponent("wt-\(UUID().uuidString)")
        try runGit(["worktree", "add", wtPath.path, "feature"], in: repoURL)
        try "dirty\n".write(to: wtPath.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)

        XCTAssertEqual(entries.first(where: { $0.path.path == wtPath.path })?.dirtyCount, 1)
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-worktree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "initial"], in: repoURL)
        try runGit(["branch", "feature"], in: repoURL)
        return repoURL
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
        _ = try runGitCapture(arguments, in: repositoryURL)
    }

    private func runGitCapture(_ arguments: [String], in repositoryURL: URL) throws -> String {
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

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if task.terminationStatus != 0 {
            throw GitError.commandFailed(error.isEmpty ? output : error)
        }

        return output
    }
}
