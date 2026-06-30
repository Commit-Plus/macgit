//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import XCTest
@testable import macgit

final class WorktreeServiceTests: XCTestCase {
    func testLockWorktreeWithReasonSetsLockedStateAndPostsRepositoryDidChange() async throws {
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

        try await GitStatusService.shared.lockWorktree(
            at: wtPath,
            reason: "Long running agent task",
            in: repoURL
        )

        await fulfillment(of: [expectation], timeout: 1.0)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        let porcelain = try runGitCapture(["worktree", "list", "--porcelain"], in: repoURL)
        XCTAssertEqual(linkedWorktree(at: wtPath, in: entries)?.isLocked, true)
        XCTAssertTrue(porcelain.contains("locked Long running agent task"))
    }

    func testLockWorktreeWithoutReasonSucceeds() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: nil,
            in: repoURL
        )

        try await GitStatusService.shared.lockWorktree(at: wtPath, reason: nil, in: repoURL)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        XCTAssertEqual(linkedWorktree(at: wtPath, in: entries)?.isLocked, true)
    }

    func testUnlockWorktreeClearsLockedStateAndPostsRepositoryDidChange() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: nil,
            in: repoURL
        )
        try runGit(["worktree", "lock", wtPath.path], in: repoURL)
        let expectation = expectation(forNotification: .repositoryDidChange, object: nil) { notification in
            (notification.userInfo?["repositoryURL"] as? URL)?.path == repoURL.path
        }

        try await GitStatusService.shared.unlockWorktree(at: wtPath, in: repoURL)

        await fulfillment(of: [expectation], timeout: 1.0)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        XCTAssertEqual(linkedWorktree(at: wtPath, in: entries)?.isLocked, false)
    }

    func testLockAndUnlockRejectMainWorktree() async throws {
        let repoURL = try makeTempRepo()

        do {
            try await GitStatusService.shared.lockWorktree(at: repoURL, reason: "no", in: repoURL)
            XCTFail("Expected lockWorktree to reject the main worktree")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("main"))
        }

        do {
            try await GitStatusService.shared.unlockWorktree(at: repoURL, in: repoURL)
            XCTFail("Expected unlockWorktree to reject the main worktree")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("main"))
        }
    }

    func testPruneWorktreesRemovesMissingLinkedWorktreeAndOrphanLabel() async throws {
        let repoURL = try makeTempRepo()
        let keptPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        let prunedPath = repoURL.appendingPathComponent(".worktrees/old-ui")
        try await GitStatusService.shared.addWorktree(
            at: keptPath,
            target: .existingBranch("feature"),
            label: "Keep",
            in: repoURL
        )
        try await GitStatusService.shared.addWorktree(
            at: prunedPath,
            target: .newBranch(name: "old-ui", base: "main"),
            label: "Prune me",
            in: repoURL
        )
        try FileManager.default.removeItem(at: prunedPath)
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)
        let expectation = expectation(forNotification: .repositoryDidChange, object: nil) { notification in
            (notification.userInfo?["repositoryURL"] as? URL)?.path == repoURL.path
        }

        try await GitStatusService.shared.pruneWorktrees(in: repoURL)

        await fulfillment(of: [expectation], timeout: 1.0)

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repoURL)
        let porcelain = try runGitCapture(["worktree", "list", "--porcelain"], in: repoURL)
        XCTAssertNotNil(linkedWorktree(at: keptPath, in: entries))
        XCTAssertNil(linkedWorktree(at: prunedPath, in: entries))
        XCTAssertTrue(porcelain.contains(keptPath.path))
        XCTAssertFalse(porcelain.contains(prunedPath.path))
        XCTAssertEqual(WorktreeLabelStore().label(for: keptPath, in: gitDirectory), "Keep")
        XCTAssertNil(WorktreeLabelStore().label(for: prunedPath, in: gitDirectory))
    }

    func testMoveWorktreeMovesDirectoryAndLabelAndPostsRepositoryDidChange() async throws {
        let repoURL = try makeTempRepo()
        let oldPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        let newPath = repoURL.appendingPathComponent(".worktrees/feature-ui-renamed")
        try await GitStatusService.shared.addWorktree(
            at: oldPath,
            target: .existingBranch("feature"),
            label: "Review UI",
            in: repoURL
        )
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)
        let expectation = expectation(forNotification: .repositoryDidChange, object: nil) { notification in
            (notification.userInfo?["repositoryURL"] as? URL)?.path == repoURL.path
        }

        try await GitStatusService.shared.moveWorktree(from: oldPath, to: newPath, in: repoURL)

        await fulfillment(of: [expectation], timeout: 1.0)

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repoURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPath.path))
        XCTAssertNil(WorktreeLabelStore().label(for: oldPath, in: gitDirectory))
        XCTAssertEqual(WorktreeLabelStore().label(for: newPath, in: gitDirectory), "Review UI")
        XCTAssertEqual(linkedWorktree(at: newPath, in: entries)?.label, "Review UI")
    }

    func testMoveWorktreeRejectsExistingTargetPath() async throws {
        let repoURL = try makeTempRepo()
        let oldPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        let newPath = repoURL.appendingPathComponent(".worktrees/existing-target")
        try await GitStatusService.shared.addWorktree(
            at: oldPath,
            target: .existingBranch("feature"),
            label: "Review UI",
            in: repoURL
        )
        try FileManager.default.createDirectory(at: newPath, withIntermediateDirectories: true)
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)

        do {
            try await GitStatusService.shared.moveWorktree(from: oldPath, to: newPath, in: repoURL)
            XCTFail("Expected moveWorktree to reject an existing target path")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: oldPath.path))
        XCTAssertEqual(WorktreeLabelStore().label(for: oldPath, in: gitDirectory), "Review UI")
        XCTAssertNil(WorktreeLabelStore().label(for: newPath, in: gitDirectory))
    }

    func testMoveWorktreeRejectsMainWorktree() async throws {
        let repoURL = try makeTempRepo()
        let newPath = repoURL.appendingPathComponent(".worktrees/main-renamed")

        do {
            try await GitStatusService.shared.moveWorktree(from: repoURL, to: newPath, in: repoURL)
            XCTFail("Expected moveWorktree to reject moving the main worktree")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("main"))
        }
    }

    func testRepairWorktreeLocationUpdatesMetadataAndLabel() async throws {
        let repoURL = try makeTempRepo()
        let oldPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        let newPath = repoURL.appendingPathComponent(".worktrees/feature-ui-moved")
        try await GitStatusService.shared.addWorktree(
            at: oldPath,
            target: .existingBranch("feature"),
            label: "Review UI",
            in: repoURL
        )
        try FileManager.default.moveItem(at: oldPath, to: newPath)
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)
        let expectation = expectation(forNotification: .repositoryDidChange, object: nil) { notification in
            (notification.userInfo?["repositoryURL"] as? URL)?.path == repoURL.path
        }

        try await GitStatusService.shared.repairWorktreeLocation(from: oldPath, to: newPath, in: repoURL)

        await fulfillment(of: [expectation], timeout: 1.0)

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repoURL)
        XCTAssertNil(linkedWorktree(at: oldPath, in: entries))
        XCTAssertEqual(linkedWorktree(at: newPath, in: entries)?.label, "Review UI")
        XCTAssertNil(WorktreeLabelStore().label(for: oldPath, in: gitDirectory))
        XCTAssertEqual(WorktreeLabelStore().label(for: newPath, in: gitDirectory), "Review UI")
    }

    func testCheckoutBranchInWorktreeSwitchesBranchAndPostsRepositoryDidChange() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try runGit(["branch", "release"], in: repoURL)
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: nil,
            in: repoURL
        )
        let expectation = expectation(forNotification: .repositoryDidChange, object: nil) { notification in
            (notification.userInfo?["repositoryURL"] as? URL)?.path == repoURL.path
        }

        try await GitStatusService.shared.checkoutBranch(
            "release",
            inWorktree: wtPath,
            force: false,
            repositoryURL: repoURL
        )

        await fulfillment(of: [expectation], timeout: 1.0)

        let entries = await GitStatusService.shared.worktrees(in: repoURL)
        let branch = try runGitCapture(["branch", "--show-current"], in: wtPath).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(branch, "release")
        XCTAssertEqual(linkedWorktree(at: wtPath, in: entries)?.branch, "release")
    }

    func testCheckoutBranchInDirtyWorktreeRequiresForce() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try createReleaseBranchWithConflictingTrackedChange(in: repoURL)
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: nil,
            in: repoURL
        )
        try "dirty\n".write(to: wtPath.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        do {
            try await GitStatusService.shared.checkoutBranch(
                "release",
                inWorktree: wtPath,
                force: false,
                repositoryURL: repoURL
            )
            XCTFail("Expected checkoutBranch to fail for a dirty worktree without force")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        let branch = try runGitCapture(["branch", "--show-current"], in: wtPath).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(branch, "feature")
        XCTAssertTrue(FileManager.default.fileExists(atPath: wtPath.appendingPathComponent("tracked.txt").path))
    }

    func testCheckoutBranchInDirtyWorktreeWithForceSucceeds() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try createReleaseBranchWithConflictingTrackedChange(in: repoURL)
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: nil,
            in: repoURL
        )
        try "dirty\n".write(to: wtPath.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)

        try await GitStatusService.shared.checkoutBranch(
            "release",
            inWorktree: wtPath,
            force: true,
            repositoryURL: repoURL
        )

        let branch = try runGitCapture(["branch", "--show-current"], in: wtPath).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(branch, "release")
    }

    func testCheckoutBranchInWorktreeRejectsMissingBranch() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: nil,
            in: repoURL
        )

        do {
            try await GitStatusService.shared.checkoutBranch(
                "missing-branch",
                inWorktree: wtPath,
                force: false,
                repositoryURL: repoURL
            )
            XCTFail("Expected checkoutBranch to reject a missing branch")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        let branch = try runGitCapture(["branch", "--show-current"], in: wtPath).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(branch, "feature")
    }

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

    func testRemoveLockedMissingWorktreeWithForceDeletesMetadataAndLabel() async throws {
        let repoURL = try makeTempRepo()
        let wtPath = repoURL.appendingPathComponent(".worktrees/feature-ui")
        try await GitStatusService.shared.addWorktree(
            at: wtPath,
            target: .existingBranch("feature"),
            label: "Review UI",
            in: repoURL
        )
        try await GitStatusService.shared.lockWorktree(at: wtPath, reason: nil, in: repoURL)
        try FileManager.default.removeItem(at: wtPath)

        try await GitStatusService.shared.removeWorktree(at: wtPath, force: true, in: repoURL)

        let entries = await GitStatusService.shared.worktreesWithLabels(in: repoURL)
        let gitDirectory = try await GitStatusService.shared.gitCommonDirectory(in: repoURL)
        XCTAssertNil(linkedWorktree(at: wtPath, in: entries))
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

    private func linkedWorktree(at path: URL, in entries: [WorktreeEntry]) -> WorktreeEntry? {
        entries.first { WorktreeLabelStore.key(for: $0.path) == WorktreeLabelStore.key(for: path) }
    }

    private func createReleaseBranchWithConflictingTrackedChange(in repositoryURL: URL) throws {
        try runGit(["checkout", "-b", "release"], in: repositoryURL)
        try "release version\n".write(
            to: repositoryURL.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["commit", "-am", "change tracked file on release"], in: repositoryURL)
        try runGit(["checkout", "main"], in: repositoryURL)
    }
}
