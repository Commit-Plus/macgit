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

final class BranchFetchActionTests: XCTestCase {
    func testFetchActionIsEnabledOnlyWhenBehindCountIsGreaterThanZero() {
        XCTAssertFalse(BranchFetchActionPolicy.shouldEnableFetch(for: nil))
        XCTAssertFalse(BranchFetchActionPolicy.shouldEnableFetch(for: BranchSyncStatus(ahead: 0, behind: 0)))
        XCTAssertTrue(BranchFetchActionPolicy.shouldEnableFetch(for: BranchSyncStatus(ahead: 0, behind: 1)))
        XCTAssertTrue(BranchFetchActionPolicy.shouldEnableFetch(for: BranchSyncStatus(ahead: 0, behind: 2)))
    }

    func testPullBranchFromUpstreamUpdatesTheCurrentBranchImmediately() async throws {
        let repoURL = try makeRepoWithFeatureBranchBehindUpstream(commitCount: 2)

        try await GitStatusService.shared.pullBranchFromUpstream(
            branch: "feature",
            in: repoURL
        )

        let fileURL = repoURL.appendingPathComponent("tracked.txt")
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content, "feature-2\n")
        let status = await GitStatusService.shared.branchSyncStatus(for: "feature", in: repoURL)
        XCTAssertNil(status)
    }

    func testPullBranchFromUpstreamHandlesDivergentBranches() async throws {
        let repoURL = try makeRepoWithDivergentFeatureBranch()

        try await GitStatusService.shared.pullBranchFromUpstream(
            branch: "feature",
            in: repoURL
        )

        let localFile = repoURL.appendingPathComponent("local.txt")
        let remoteFile = repoURL.appendingPathComponent("remote.txt")
        let gitStatus = try runGitAndCapture(["status", "--short"], in: repoURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: localFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: remoteFile.path))
        XCTAssertEqual(gitStatus.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testFetchBranchUpdatesRemoteTrackingBranchWithoutMerging() async throws {
        let repoURL = try makeRepoWithFeatureBranchBehindUpstream(commitCount: 2)

        let localTipBefore = try runGitAndCapture(["rev-parse", "feature"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteTrackingBefore = try runGitAndCapture(["rev-parse", "origin/feature"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let workingCopy = repoURL.appendingPathComponent("tracked.txt")
        let workingCopyBefore = try String(contentsOf: workingCopy, encoding: .utf8)

        // The remote-tracking ref starts out stale (still pointing at the local
        // tip because the local clone predates the updater's pushes).
        XCTAssertEqual(localTipBefore, remoteTrackingBefore)

        try await GitStatusService.shared.fetchBranch(
            remote: "origin",
            branch: "feature",
            in: repoURL
        )

        let localTipAfter = try runGitAndCapture(["rev-parse", "feature"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteTrackingAfter = try runGitAndCapture(["rev-parse", "origin/feature"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let workingCopyAfter = try String(contentsOf: workingCopy, encoding: .utf8)

        // Fetch must not touch the local branch tip or the working copy.
        XCTAssertEqual(localTipBefore, localTipAfter)
        XCTAssertEqual(workingCopyBefore, workingCopyAfter)
        // The remote-tracking branch should have caught up to the latest upstream.
        XCTAssertNotEqual(remoteTrackingAfter, localTipAfter)
        XCTAssertNotEqual(remoteTrackingAfter, remoteTrackingBefore)
    }

    func testFetchAndFastForwardBranchUpdatesSelectedNonCurrentBranch() async throws {
        let repoURL = try makeRepoWithMainBehindWhileFeatureIsCurrent()

        let currentBefore = try runGitAndCapture(["branch", "--show-current"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mainBefore = try runGitAndCapture(["rev-parse", "main"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteMainBefore = try runGitAndCapture(["rev-parse", "origin/main"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(currentBefore, "feature")
        XCTAssertEqual(mainBefore, remoteMainBefore)

        try await GitStatusService.shared.fetchAndFastForwardBranchFromUpstream(
            branch: "main",
            in: repoURL
        )

        let currentAfter = try runGitAndCapture(["branch", "--show-current"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mainAfter = try runGitAndCapture(["rev-parse", "main"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteMainAfter = try runGitAndCapture(["rev-parse", "origin/main"], in: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let workingCopy = try String(contentsOf: repoURL.appendingPathComponent("tracked.txt"), encoding: .utf8)

        XCTAssertEqual(currentAfter, "feature")
        XCTAssertNotEqual(mainAfter, mainBefore)
        XCTAssertEqual(mainAfter, remoteMainAfter)
        XCTAssertEqual(workingCopy, "feature\n")
    }

    func testFetchBranchThrowsWhenRemoteDoesNotHaveTheBranch() async throws {
        let repoURL = try makeRepoWithFeatureBranchBehindUpstream(commitCount: 1)

        do {
            try await GitStatusService.shared.fetchBranch(
                remote: "origin",
                branch: "nonexistent",
                in: repoURL
            )
            XCTFail("Expected fetch to throw on unknown branch")
        } catch {
            // Expected: git fetch prints 'couldn't find remote ref' and exits non-zero.
        }
    }

    // MARK: - Helpers

    private func makeRepoWithFeatureBranchBehindUpstream(commitCount: Int) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-branch-fetch-\(UUID().uuidString)", isDirectory: true)
        let originURL = rootURL.appendingPathComponent("origin.git", isDirectory: true)
        let localURL = rootURL.appendingPathComponent("local", isDirectory: true)
        let updaterURL = rootURL.appendingPathComponent("updater", isDirectory: true)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try runGit(["init", "--bare", "--initial-branch=main", originURL.path], in: rootURL)
        try runGit(["clone", originURL.path, localURL.path], in: rootURL)
        try configureGit(in: localURL)

        let trackedFile = localURL.appendingPathComponent("tracked.txt")
        try "main-0\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "main 0"], in: localURL)
        try runGit(["push", "-u", "origin", "main"], in: localURL)

        try runGit(["checkout", "-b", "feature"], in: localURL)
        try "feature-0\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "feature 0"], in: localURL)
        try runGit(["push", "-u", "origin", "feature"], in: localURL)

        try runGit(["clone", originURL.path, updaterURL.path], in: rootURL)
        try configureGit(in: updaterURL)
        try runGit(["checkout", "-b", "feature", "origin/feature"], in: updaterURL)

        for index in 1...commitCount {
            try "feature-\(index)\n".write(to: trackedFile.replacingPathComponent(in: updaterURL), atomically: true, encoding: .utf8)
            try runGit(["add", "tracked.txt"], in: updaterURL)
            try runGit(["commit", "-m", "feature \(index)"], in: updaterURL)
        }

        try runGit(["push"], in: updaterURL)

        return localURL
    }

    private func makeRepoWithDivergentFeatureBranch() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-branch-divergent-\(UUID().uuidString)", isDirectory: true)
        let originURL = rootURL.appendingPathComponent("origin.git", isDirectory: true)
        let localURL = rootURL.appendingPathComponent("local", isDirectory: true)
        let updaterURL = rootURL.appendingPathComponent("updater", isDirectory: true)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try runGit(["init", "--bare", "--initial-branch=main", originURL.path], in: rootURL)
        try runGit(["clone", originURL.path, localURL.path], in: rootURL)
        try configureGit(in: localURL)

        let baseFile = localURL.appendingPathComponent("base.txt")
        try "base\n".write(to: baseFile, atomically: true, encoding: .utf8)
        try runGit(["add", "base.txt"], in: localURL)
        try runGit(["commit", "-m", "base"], in: localURL)
        try runGit(["push", "-u", "origin", "main"], in: localURL)

        try runGit(["checkout", "-b", "feature"], in: localURL)
        let localFile = localURL.appendingPathComponent("local.txt")
        try "local\n".write(to: localFile, atomically: true, encoding: .utf8)
        try runGit(["add", "local.txt"], in: localURL)
        try runGit(["commit", "-m", "local"], in: localURL)
        try runGit(["push", "-u", "origin", "feature"], in: localURL)

        try runGit(["clone", originURL.path, updaterURL.path], in: rootURL)
        try configureGit(in: updaterURL)
        try runGit(["checkout", "-b", "feature", "origin/feature"], in: updaterURL)
        let remoteFile = updaterURL.appendingPathComponent("remote.txt")
        try "remote\n".write(to: remoteFile, atomically: true, encoding: .utf8)
        try runGit(["add", "remote.txt"], in: updaterURL)
        try runGit(["commit", "-m", "remote"], in: updaterURL)
        try runGit(["push"], in: updaterURL)

        return localURL
    }

    private func makeRepoWithMainBehindWhileFeatureIsCurrent() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-branch-main-behind-\(UUID().uuidString)", isDirectory: true)
        let originURL = rootURL.appendingPathComponent("origin.git", isDirectory: true)
        let localURL = rootURL.appendingPathComponent("local", isDirectory: true)
        let updaterURL = rootURL.appendingPathComponent("updater", isDirectory: true)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try runGit(["init", "--bare", "--initial-branch=main", originURL.path], in: rootURL)
        try runGit(["clone", originURL.path, localURL.path], in: rootURL)
        try configureGit(in: localURL)

        let trackedFile = localURL.appendingPathComponent("tracked.txt")
        try "main-0\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "main 0"], in: localURL)
        try runGit(["push", "-u", "origin", "main"], in: localURL)

        try runGit(["checkout", "-b", "feature"], in: localURL)
        try "feature\n".write(to: trackedFile, atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: localURL)
        try runGit(["commit", "-m", "feature"], in: localURL)

        try runGit(["clone", originURL.path, updaterURL.path], in: rootURL)
        try configureGit(in: updaterURL)
        try "main-1\n".write(to: trackedFile.replacingPathComponent(in: updaterURL), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: updaterURL)
        try runGit(["commit", "-m", "main 1"], in: updaterURL)
        try runGit(["push"], in: updaterURL)

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

    private func runGitAndCapture(_ arguments: [String], in repositoryURL: URL) throws -> String {
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

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        if task.terminationStatus != 0 {
            let error = String(data: errorData, encoding: .utf8) ?? "git failed"
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(error)")
        }
        return output
    }
}

private extension URL {
    func replacingPathComponent(in directory: URL) -> URL {
        directory.appendingPathComponent(lastPathComponent)
    }
}
