import XCTest
@testable import macgit

final class WorktreeLabelStoreTests: XCTestCase {
    func testMissingLabelFileReadsAsEmptyDictionary() throws {
        let gitDirectory = try makeTempGitDirectory()
        let store = WorktreeLabelStore()

        XCTAssertEqual(store.labels(in: gitDirectory), [:])
    }

    func testCorruptLabelFileReadsAsEmptyDictionary() throws {
        let gitDirectory = try makeTempGitDirectory()
        let labelsURL = labelFileURL(in: gitDirectory)
        try FileManager.default.createDirectory(
            at: labelsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{bad-json".utf8).write(to: labelsURL)

        let store = WorktreeLabelStore()

        XCTAssertEqual(store.labels(in: gitDirectory), [:])
    }

    func testSetLabelTrimsAndPersistsNormalizedPath() throws {
        let gitDirectory = try makeTempGitDirectory()
        let worktreePath = URL(fileURLWithPath: "/tmp/macgit-label-worktree")
        let store = WorktreeLabelStore()

        try store.setLabel("  Agent task  ", for: worktreePath, in: gitDirectory)

        XCTAssertEqual(
            store.labels(in: gitDirectory)[WorktreeLabelStore.key(for: worktreePath)],
            "Agent task"
        )
        XCTAssertEqual(store.label(for: worktreePath, in: gitDirectory), "Agent task")
    }

    func testBlankLabelRemovesStoredValue() throws {
        let gitDirectory = try makeTempGitDirectory()
        let worktreePath = URL(fileURLWithPath: "/tmp/macgit-label-worktree")
        let store = WorktreeLabelStore()

        try store.setLabel("Review UI", for: worktreePath, in: gitDirectory)
        try store.setLabel("   ", for: worktreePath, in: gitDirectory)

        XCTAssertNil(store.label(for: worktreePath, in: gitDirectory))
        XCTAssertEqual(store.labels(in: gitDirectory), [:])
    }

    func testMoveLabelTransfersValueToNewPath() throws {
        let gitDirectory = try makeTempGitDirectory()
        let oldPath = URL(fileURLWithPath: "/tmp/macgit-old-worktree")
        let newPath = URL(fileURLWithPath: "/tmp/macgit-new-worktree")
        let store = WorktreeLabelStore()

        try store.setLabel("Review UI", for: oldPath, in: gitDirectory)
        try store.moveLabel(from: oldPath, to: newPath, in: gitDirectory)

        XCTAssertNil(store.label(for: oldPath, in: gitDirectory))
        XCTAssertEqual(store.label(for: newPath, in: gitDirectory), "Review UI")
    }

    func testPruneRemovesOrphanedLabels() throws {
        let gitDirectory = try makeTempGitDirectory()
        let keptPath = URL(fileURLWithPath: "/tmp/macgit-kept-worktree")
        let orphanPath = URL(fileURLWithPath: "/tmp/macgit-orphan-worktree")
        let store = WorktreeLabelStore()

        try store.setLabel("Keep", for: keptPath, in: gitDirectory)
        try store.setLabel("Remove", for: orphanPath, in: gitDirectory)

        let pruned = try store.prune(validPaths: Set([keptPath]), in: gitDirectory)

        XCTAssertEqual(pruned, [WorktreeLabelStore.key(for: keptPath): "Keep"])
        XCTAssertNil(store.label(for: orphanPath, in: gitDirectory))
    }

    private func makeTempGitDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-worktree-label-store-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func labelFileURL(in gitDirectory: URL) -> URL {
        gitDirectory
            .appendingPathComponent("macgit", isDirectory: true)
            .appendingPathComponent("worktree-labels.json")
    }
}
