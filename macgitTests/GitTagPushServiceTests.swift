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

final class GitTagPushServiceTests: XCTestCase {
    func testPushSelectedTagDoesNotPushOtherLocalTags() async throws {
        let sourceURL = try makeRepository()
        let remoteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-tag-remote-\(UUID().uuidString).git", isDirectory: true)
        try runGit(["init", "--bare", remoteURL.path], in: sourceURL)
        try runGit(["remote", "add", "origin", remoteURL.path], in: sourceURL)
        try runGit(["tag", "v1.0.0"], in: sourceURL)
        try runGit(["tag", "v2.0.0"], in: sourceURL)

        let options = GitStatusService.PushOptions(remote: "origin", tags: ["v1.0.0"])
        _ = try await GitStatusService.shared.push(options: options, in: sourceURL)

        XCTAssertTrue(try refExists("refs/tags/v1.0.0", in: remoteURL))
        XCTAssertFalse(try refExists("refs/tags/v2.0.0", in: remoteURL))
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-tag-push-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
        try "release\n".write(
            to: repositoryURL.appendingPathComponent("release.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "release.txt"], in: repositoryURL)
        try runGit(["commit", "-m", "Release"], in: repositoryURL)
        return repositoryURL
    }

    private func refExists(_ ref: String, in repositoryURL: URL) throws -> Bool {
        do {
            try runGit(["show-ref", "--verify", "--quiet", ref], in: repositoryURL)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func runGit(_ arguments: [String], in repositoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        if process.terminationStatus != 0 {
            let error = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            throw NSError(
                domain: "GitTagPushServiceTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: error]
            )
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
