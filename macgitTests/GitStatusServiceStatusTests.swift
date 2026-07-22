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

@MainActor
final class GitStatusServiceStatusTests: XCTestCase {
    func testStatusIncludesUntrackedBinaryFile() async throws {
        let repoURL = try makeTempRepo()
        let fileURL = repoURL.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]).write(to: fileURL)

        let status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(status.untracked.contains { $0.path == "clip.mp4" }, "Untracked .mp4 file should appear in status")
    }

    func testStatusIncludesModifiedBinaryFile() async throws {
        let repoURL = try makeTempRepo()
        let fileURL = repoURL.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]).write(to: fileURL)
        try runGit(["add", "clip.mp4"], in: repoURL)
        try runGit(["commit", "-m", "add video"], in: repoURL)

        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0xAA]).write(to: fileURL)

        let status = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertTrue(status.unstaged.contains { $0.path == "clip.mp4" }, "Modified tracked .mp4 file should appear in status")
    }

    func testStatusDrainsLargeUntrackedOutputWithoutDeadlocking() async throws {
        let repoURL = try makeTempRepo()
        let filesURL = repoURL.appendingPathComponent("generated", isDirectory: true)
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)

        let fileCount = 2_000
        for index in 0..<fileCount {
            let filename = String(format: "generated-file-%04d-with-a-long-name-to-exceed-the-process-pipe-buffer.txt", index)
            try Data().write(to: filesURL.appendingPathComponent(filename))
        }

        let status = try await GitStatusService.shared.status(for: repoURL)
        let count = await GitStatusService.shared.uncommittedChangeCount(in: repoURL)

        XCTAssertEqual(status.untracked.count, fileCount)
        XCTAssertEqual(count, fileCount)
    }

    private func makeTempRepo() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-status-binary-\(UUID().uuidString)", isDirectory: true)
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
