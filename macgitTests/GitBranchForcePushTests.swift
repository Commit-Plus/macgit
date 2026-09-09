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
final class GitBranchForcePushTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var remote: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("branch-force-push-\(UUID())")
        source = root.appendingPathComponent("source")
        remote = root.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try git(["init", "-b", "main"])
        try git(["config", "user.name", "Tests"])
        try git(["config", "user.email", "tests@example.com"])
        try git(["commit", "--allow-empty", "-m", "base"])
        try git(["commit", "--allow-empty", "-m", "published"])
        try git(["init", "--bare", remote.path])
        try git(["remote", "add", "origin", remote.path])
        try git(["push", "origin", "main:refs/heads/review/topic", "main:refs/heads/untouched"])
        try git(["reset", "--soft", "HEAD^"])
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func testResetMappedBranchAndGuardedUndoRedo() async throws {
        let plan = try await prepare()
        XCTAssertEqual(plan.removedCommitCount, 1)
        let untouched = try remoteTip("untouched")
        try git(["tag", "-a", "local-only", "-m", "do not publish"])
        try git(["config", "push.followTags", "true"])
        try git(["config", "remote.origin.push", "refs/heads/main:refs/heads/untouched"])
        try await GitStatusService.shared.forcePushBranch(plan, in: source)
        XCTAssertEqual(try remoteTip("review/topic"), plan.localHash)
        XCTAssertEqual(try remoteTip("untouched"), untouched)
        XCTAssertEqual(try git(["ls-remote", "origin", "refs/tags/local-only"]), "")
        try await GitStatusService.shared.replaceRemoteBranch(plan, restoring: true, in: source)
        XCTAssertEqual(try remoteTip("review/topic"), plan.remoteHash)
        try await GitStatusService.shared.replaceRemoteBranch(plan, restoring: false, in: source)
        XCTAssertEqual(try remoteTip("review/topic"), plan.localHash)
        // Undo must reject a collaborator's later update.
        try git(["push", "origin", "\(plan.remoteHash):refs/heads/review/topic"])
        await expectFailure { try await GitStatusService.shared.replaceRemoteBranch(plan, restoring: true, in: self.source) }
        XCTAssertEqual(try remoteTip("review/topic"), plan.remoteHash)
    }

    func testDivergedBranchCanReplaceRemote() async throws {
        try git(["commit", "--allow-empty", "-m", "replacement"])
        let plan = try await prepare()
        XCTAssertEqual(plan.removedCommitCount, 1)
        try await GitStatusService.shared.forcePushBranch(plan, in: source)
        XCTAssertEqual(try remoteTip("review/topic"), plan.localHash)
    }

    func testCustomDefaultBranchIsFlagged() async throws {
        try git(["--git-dir", remote.path, "symbolic-ref", "HEAD", "refs/heads/review/topic"])
        let plan = try await prepare()
        XCTAssertTrue(plan.isDefaultBranch)
    }

    func testRemoteAdvanceRejectedEvenAfterBackgroundFetch() async throws {
        let plan = try await prepare()
        try git(["checkout", "-b", "collaborator", plan.remoteHash])
        try git(["commit", "--allow-empty", "-m", "collaborator"])
        let advanced = try git(["rev-parse", "HEAD"])
        try git(["push", "origin", "HEAD:refs/heads/review/topic"])
        try git(["checkout", "main"])
        try git(["fetch", "origin"])
        await expectFailure { try await GitStatusService.shared.forcePushBranch(plan, in: self.source) }
        XCTAssertEqual(try remoteTip("review/topic"), advanced)
    }

    func testLocalChangeRejected() async throws {
        let plan = try await prepare()
        try git(["commit", "--allow-empty", "-m", "changed after confirmation"])
        await expectFailure { try await GitStatusService.shared.forcePushBranch(plan, in: self.source) }
        XCTAssertEqual(try remoteTip("review/topic"), plan.remoteHash)
    }

    func testDeletedRemoteIsNotRecreated() async throws {
        let plan = try await prepare()
        try git(["push", "origin", "--delete", "review/topic"])
        await expectFailure { try await GitStatusService.shared.forcePushBranch(plan, in: self.source) }
        XCTAssertEqual(try git(["ls-remote", "origin", "refs/heads/review/topic"]), "")
    }

    func testServerProtectionIsRespected() async throws {
        let plan = try await prepare()
        try git(["--git-dir", remote.path, "config", "receive.denyNonFastForwards", "true"])
        await expectFailure { try await GitStatusService.shared.forcePushBranch(plan, in: self.source) }
        XCTAssertEqual(try remoteTip("review/topic"), plan.remoteHash)
    }

    func testMissingDestinationCannotBeForcePublished() async throws {
        try git(["push", "origin", "--delete", "review/topic"])
        await expectFailure { _ = try await self.prepare() }
    }

    func testChangedEndpointRejected() async throws {
        let plan = try await prepare()
        let other = root.appendingPathComponent("other.git")
        try git(["init", "--bare", other.path])
        try git(["remote", "set-url", "origin", other.path])
        await expectFailure { try await GitStatusService.shared.forcePushBranch(plan, in: self.source) }
        XCTAssertEqual(try git(["--git-dir", remote.path, "rev-parse", "refs/heads/review/topic"]), plan.remoteHash)
    }

    func testMultiplePushURLsRejected() async throws {
        try git(["config", "--add", "remote.origin.pushurl", remote.path])
        try git(["config", "--add", "remote.origin.pushurl", root.appendingPathComponent("other.git").path])
        await expectFailure { _ = try await self.prepare() }
    }

    func testFastForwardDoesNotOfferDestructiveConfirmation() async throws {
        try git(["reset", "--soft", "refs/remotes/origin/review/topic"])
        try git(["commit", "--allow-empty", "-m", "ordinary update"])
        await expectFailure { _ = try await self.prepare() }
    }

    func testPushDestinationsOmitOnlyExactTrackedMapping() {
        XCTAssertEqual(BranchUpstreamActionPolicy.pushRemotes(
            branch: "main", upstream: "origin/main", remotes: ["origin", "backup"]
        ), ["backup"])
        XCTAssertEqual(BranchUpstreamActionPolicy.pushRemotes(
            branch: "main", upstream: "origin/review/topic", remotes: ["origin"]
        ), ["origin"])
        XCTAssertEqual(BranchUpstreamActionPolicy.pushRemotes(
            branch: "main", upstream: nil, remotes: ["origin"]
        ), ["origin"])
    }

    private func prepare() async throws -> BranchForcePushPlan {
        try await GitStatusService.shared.prepareBranchForcePush(
            remote: "origin", localBranch: "main", remoteBranch: "review/topic", in: source
        )
    }

    private func expectFailure(_ action: () async throws -> Void) async {
        do {
            try await action()
            XCTFail("Expected the operation to reject stale or invalid state")
        } catch {}
    }

    private func remoteTip(_ branch: String) throws -> String {
        try git(["--git-dir", remote.path, "rev-parse", "refs/heads/\(branch)"])
    }

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = source
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GitBranchForcePushTests", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: output])
        }
        return output
    }
}
