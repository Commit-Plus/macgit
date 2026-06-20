//
//  GitFileUndoSnapshotStoreTests.swift
//  macgitTests
//

import XCTest
@testable import macgit

final class GitFileUndoSnapshotStoreTests: XCTestCase {
    func testCaptureAndRestoreExistingFile() throws {
        let repoURL = try makeRepoDirectory()
        let fileURL = repoURL.appendingPathComponent("Notes.txt")
        try "before\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = GitFileUndoSnapshotStore()

        let snapshot = try store.capture(paths: ["Notes.txt"], in: repoURL)
        try "after\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try store.restore(snapshotID: snapshot.id, in: repoURL)

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "before\n")
    }

    func testCaptureAndRestoreMissingFileRemovesCurrentFile() throws {
        let repoURL = try makeRepoDirectory()
        let store = GitFileUndoSnapshotStore()

        let snapshot = try store.capture(paths: ["Missing.txt"], in: repoURL)
        try "created later\n".write(to: repoURL.appendingPathComponent("Missing.txt"), atomically: true, encoding: .utf8)
        try store.restore(snapshotID: snapshot.id, in: repoURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("Missing.txt").path))
    }

    private func makeRepoDirectory() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-file-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL.appendingPathComponent(".git"), withIntermediateDirectories: true)
        return repoURL
    }
}
