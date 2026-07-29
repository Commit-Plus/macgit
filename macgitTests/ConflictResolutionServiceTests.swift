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

final class ConflictResolutionServiceTests: XCTestCase {
    func testConflictedFileAppearsInBothStatusSections() async throws {
        let repoURL = try makeConflictedRepository()

        let status = try await GitStatusService.shared.status(for: repoURL)

        XCTAssertTrue(status.staged.contains {
            $0.path == "tracked.txt" && $0.status == .conflict
        })
        XCTAssertTrue(status.unstaged.contains {
            $0.path == "tracked.txt" && $0.status == .conflict
        })
    }

    func testLoadConflictDocumentReadsCurrentAndIncomingStages() async throws {
        let repoURL = try makeConflictedRepository()

        let status = try await GitStatusService.shared.status(for: repoURL)
        let file = try XCTUnwrap(status.unstaged.first(where: { $0.status == .conflict }))

        let document = try await GitStatusService.shared.conflictDocument(for: file, in: repoURL)

        XCTAssertEqual(document.currentContent, "main change\n")
        XCTAssertEqual(document.incomingContent, "feature change\n")
        XCTAssertTrue(document.sections.contains(where: { $0.currentText == "main change\n" }))
        XCTAssertTrue(document.sections.contains(where: { $0.incomingText == "feature change\n" }))
    }

    func testSaveManualResolutionWritesResolvedContentAndStagesFile() async throws {
        let repoURL = try makeConflictedRepository()
        let status = try await GitStatusService.shared.status(for: repoURL)
        let file = try XCTUnwrap(status.unstaged.first(where: { $0.status == .conflict }))
        var document = try await GitStatusService.shared.conflictDocument(for: file, in: repoURL)
        let conflictIndex = try XCTUnwrap(document.sections.firstIndex(where: { $0.isConflict }))
        document.sections[conflictIndex].manualResult = "main change\nfeature change\n"

        try await GitStatusService.shared.resolveConflict(
            file: file,
            in: repoURL,
            with: document
        )

        let fileText = try String(contentsOf: repoURL.appendingPathComponent(file.path), encoding: .utf8)
        XCTAssertEqual(fileText, "main change\nfeature change\n")

        let refreshed = try await GitStatusService.shared.status(for: repoURL)
        XCTAssertFalse(refreshed.staged.contains(where: {
            $0.path == file.path && $0.status == .conflict
        }))
        XCTAssertFalse(refreshed.unstaged.contains(where: {
            $0.path == file.path && $0.status == .conflict
        }))
        XCTAssertTrue(refreshed.staged.contains(where: { $0.path == file.path }))
    }

    private func makeConflictedRepository() throws -> URL {
        let repoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-conflict-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repoURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repoURL)

        let trackedFile = repoURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: repoURL)
        try runGit(["commit", "-m", "base"], in: repoURL)

        try runGit(["checkout", "-b", "feature"], in: repoURL)
        try "feature change\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "feature change"], in: repoURL)

        try runGit(["checkout", "main"], in: repoURL)
        try "main change\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "main change"], in: repoURL)

        _ = try runGitAllowingFailure(["merge", "feature"], in: repoURL)

        return repoURL
    }

    @discardableResult
    private func runGit(_ arguments: [String], in repositoryURL: URL) throws -> String {
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
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(error)")
        }

        return output
    }

    private func runGitAllowingFailure(_ arguments: [String], in repositoryURL: URL) throws -> String {
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
        return output + error
    }
}
