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

final class GitTagServiceTests: XCTestCase {
    func testLightweightTagDetailsResolveCommitMetadata() async throws {
        let repositoryURL = try makeRepository()
        try runGit(["tag", "v1.0.0"], in: repositoryURL)

        let details = try await GitStatusService.shared.tagDetails(
            name: "v1.0.0",
            in: repositoryURL
        )

        XCTAssertEqual(details.name, "v1.0.0")
        XCTAssertEqual(details.commitHash, try runGit(["rev-parse", "HEAD"], in: repositoryURL))
        XCTAssertEqual(details.authorName, "Mac Git Tests")
        XCTAssertEqual(details.authorEmail, "tests@example.com")
        XCTAssertEqual(details.subject, "Release subject")
        XCTAssertEqual(details.body, "Release body")
        XCTAssertEqual(
            ISO8601DateFormatter().string(from: details.date),
            "2026-07-11T08:30:00Z"
        )
    }

    func testAnnotatedTagDetailsPeelToCommitMetadata() async throws {
        let repositoryURL = try makeRepository()
        try runGit(["tag", "-a", "v1.0.0", "-m", "Annotated tag message"], in: repositoryURL)

        let details = try await GitStatusService.shared.tagDetails(
            name: "v1.0.0",
            in: repositoryURL
        )

        XCTAssertEqual(details.commitHash, try runGit(["rev-parse", "HEAD"], in: repositoryURL))
        XCTAssertEqual(details.subject, "Release subject")
        XCTAssertEqual(details.body, "Release body")
    }

    func testDeleteTagRemovesOnlyTheSelectedLocalTag() async throws {
        let repositoryURL = try makeRepository()
        try runGit(["tag", "v1.0.0"], in: repositoryURL)
        try runGit(["tag", "v2.0.0"], in: repositoryURL)

        try await GitStatusService.shared.deleteTag(name: "v1.0.0", in: repositoryURL)

        let tags = await GitStatusService.shared.tags(in: repositoryURL)
        XCTAssertEqual(tags, ["v2.0.0"])
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-tag-service-\(UUID().uuidString)", isDirectory: true)
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
        try runGit(
            ["commit", "-m", "Release subject", "-m", "Release body"],
            in: repositoryURL,
            environment: [
                "GIT_AUTHOR_DATE": "2026-07-11T08:30:00Z",
                "GIT_COMMITTER_DATE": "2026-07-11T08:30:00Z"
            ]
        )
        return repositoryURL
    }

    @discardableResult
    private func runGit(
        _ arguments: [String],
        in repositoryURL: URL,
        environment: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }

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
                domain: "GitTagServiceTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: error]
            )
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
