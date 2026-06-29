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

final class BranchUpstreamServiceTests: XCTestCase {
    func testSetUpstreamStoresTheFullUpstreamRef() async throws {
        let repoURL = try makeRepoWithRemote(featureBranch: "feature")

        try await GitStatusService.shared.setUpstream(
            upstream: "origin/feature",
            branch: "feature",
            in: repoURL
        )

        let upstream = await GitStatusService.shared.upstreamBranch(for: "feature", in: repoURL)
        XCTAssertEqual(upstream, "origin/feature")
    }

    func testUnsetUpstreamClearsTheTrackedUpstream() async throws {
        let repoURL = try makeRepoWithRemote(featureBranch: "feature")

        let before = await GitStatusService.shared.upstreamBranch(for: "feature", in: repoURL)
        XCTAssertEqual(before, "origin/feature")

        try await GitStatusService.shared.unsetUpstream(branch: "feature", in: repoURL)

        let after = await GitStatusService.shared.upstreamBranch(for: "feature", in: repoURL)
        XCTAssertNil(after)
    }

    func testLocalBranchUpstreamsReportsAllTrackedBranches() async throws {
        let repoURL = try makeRepoWithRemote(featureBranch: "feature")

        let upstreams = await GitStatusService.shared.localBranchUpstreams(in: repoURL)

        XCTAssertEqual(upstreams["main"], "origin/main")
        XCTAssertEqual(upstreams["feature"], "origin/feature")
    }

    func testLocalBranchUpstreamsOmitsUntrackedBranches() async throws {
        let repoURL = try makeRepoWithRemote(featureBranch: "feature")
        try runGit(["checkout", "-b", "untracked"], in: repoURL)

        let upstreams = await GitStatusService.shared.localBranchUpstreams(in: repoURL)

        XCTAssertEqual(upstreams["main"], "origin/main")
        XCTAssertEqual(upstreams["feature"], "origin/feature")
        XCTAssertNil(upstreams["untracked"])
    }

    // MARK: - Helpers

    private func makeRepoWithRemote(featureBranch: String) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-branch-upstream-\(UUID().uuidString)", isDirectory: true)
        let originURL = rootURL.appendingPathComponent("origin.git", isDirectory: true)
        let localURL = rootURL.appendingPathComponent("local", isDirectory: true)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try runGit(["init", "--bare", "--initial-branch=main", originURL.path], in: rootURL)
        try runGit(["clone", originURL.path, localURL.path], in: rootURL)
        try configureGit(in: localURL)

        let file = localURL.appendingPathComponent("tracked.txt")
        try "base\n".write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "base"], in: localURL)
        try runGit(["push", "-u", "origin", "main"], in: localURL)

        try runGit(["checkout", "-b", featureBranch], in: localURL)
        try "feature\n".write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "feature"], in: localURL)
        try runGit(["push", "-u", "origin", featureBranch], in: localURL)

        try runGit(["checkout", "main"], in: localURL)

        return localURL
    }

    private func configureGit(in repositoryURL: URL) throws {
        try runGit(["config", "user.name", "Mac Git Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "tests@example.com"], in: repositoryURL)
    }

    private func runGit(_ arguments: [String], in repositoryURL: URL) throws {
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

        if task.terminationStatus != 0 {
            let outputData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "git failed"
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(output)")
        }
    }
}
