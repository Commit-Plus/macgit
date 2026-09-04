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

final class RepositoryAIRemoteOperationIntegrationTests: XCTestCase {
    @MainActor
    func testConfirmedFetchUpdatesOnlyRemoteTrackingState() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let oldHead = try gitOutput(["rev-parse", "HEAD"], in: fixture.localURL)
        let oldTracking = try gitOutput(["rev-parse", "origin/main"], in: fixture.localURL)
        try addCommitAndPush("remote update", file: "remote.txt", in: fixture.peerURL)

        let environment = makeEnvironment()
        let context = try await environment.contextProvider.context(in: fixture.localURL)
        let remote = try XCTUnwrap(context.remotes.first { $0.name == "origin" })
        let operation = try RepositoryAIRemoteOperationPolicy.validate(
            .fetch(remoteID: remote.id),
            context: context
        )

        XCTAssertEqual(try gitOutput(["rev-parse", "origin/main"], in: fixture.localURL), oldTracking)
        let result = try await environment.executor.execute(operation, in: fixture.localURL)

        XCTAssertEqual(try gitOutput(["rev-parse", "HEAD"], in: fixture.localURL), oldHead)
        XCTAssertNotEqual(try gitOutput(["rev-parse", "origin/main"], in: fixture.localURL), oldTracking)
        XCTAssertTrue(result.summary.hasPrefix("Succeeded"))
    }

    @MainActor
    func testConfirmedFastForwardPullUpdatesHeadAndRegistersUndo() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let oldHead = try gitOutput(["rev-parse", "HEAD"], in: fixture.localURL)
        try addCommitAndPush("remote update", file: "remote.txt", in: fixture.peerURL)
        try runGit(["fetch", "origin"], in: fixture.localURL)

        let environment = makeEnvironment()
        let context = try await environment.contextProvider.context(in: fixture.localURL)
        let branch = try XCTUnwrap(context.currentBranch)
        let operation = try RepositoryAIRemoteOperationPolicy.validate(
            .pullFastForward(remoteID: branch.remoteID, branchID: branch.id),
            context: context
        )
        XCTAssertEqual(branch.commitsBehind, 1)

        _ = try await environment.executor.execute(operation, in: fixture.localURL)

        XCTAssertNotEqual(try gitOutput(["rev-parse", "HEAD"], in: fixture.localURL), oldHead)
        XCTAssertEqual(
            try gitOutput(["rev-parse", "HEAD"], in: fixture.localURL),
            try gitOutput(["rev-parse", "origin/main"], in: fixture.localURL)
        )
        XCTAssertEqual(environment.undoManager.undoStack.last?.label, "Pull")
    }

    @MainActor
    func testConfirmedOrdinaryPushUpdatesConfiguredUpstream() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try addCommit("local update", file: "local.txt", in: fixture.localURL)

        let environment = makeEnvironment()
        let context = try await environment.contextProvider.context(in: fixture.localURL)
        let branch = try XCTUnwrap(context.currentBranch)
        let operation = try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: branch.remoteID),
            context: context
        )
        XCTAssertEqual(branch.commitsAhead, 1)

        _ = try await environment.executor.execute(operation, in: fixture.localURL)

        XCTAssertEqual(
            try gitOutput(["rev-parse", "HEAD"], in: fixture.localURL),
            try gitOutput(["rev-parse", "refs/heads/main"], in: fixture.remoteURL)
        )
    }

    func testRealRepositoryMissingAndDivergedUpstreamAreRejected() async throws {
        let missingFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: missingFixture.rootURL) }
        try runGit(["branch", "--unset-upstream"], in: missingFixture.localURL)
        let provider = RepositoryAIRemoteOperationContextProvider()
        var context = try await provider.context(in: missingFixture.localURL)
        let remote = try XCTUnwrap(context.remotes.first)
        XCTAssertNil(context.currentBranch)
        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: remote.id),
            context: context
        ))

        let divergedFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: divergedFixture.rootURL) }
        try addCommit("local update", file: "local.txt", in: divergedFixture.localURL)
        try addCommitAndPush("remote update", file: "remote.txt", in: divergedFixture.peerURL)
        try runGit(["fetch", "origin"], in: divergedFixture.localURL)
        context = try await provider.context(in: divergedFixture.localURL)
        let branch = try XCTUnwrap(context.currentBranch)
        XCTAssertEqual(branch.commitsAhead, 1)
        XCTAssertEqual(branch.commitsBehind, 1)
        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pullFastForward(remoteID: branch.remoteID, branchID: branch.id),
            context: context
        ))
        XCTAssertThrowsError(try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: branch.remoteID),
            context: context
        ))
    }

    @MainActor
    func testStaleRemoteTrackingRefPreventsExecution() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try addCommit("local update", file: "local.txt", in: fixture.localURL)
        let environment = makeEnvironment()
        let context = try await environment.contextProvider.context(in: fixture.localURL)
        let branch = try XCTUnwrap(context.currentBranch)
        let operation = try RepositoryAIRemoteOperationPolicy.validate(
            .pushCurrentBranch(remoteID: branch.remoteID),
            context: context
        )
        try runGit(["update-ref", "refs/remotes/origin/main", "HEAD"], in: fixture.localURL)

        do {
            _ = try await environment.executor.execute(operation, in: fixture.localURL)
            XCTFail("Expected stale proposal rejection")
        } catch let error as RepositoryAIRemoteOperationError {
            guard case .stale = error else { return XCTFail("Expected stale, got \(error)") }
        }
        XCTAssertNotEqual(
            try gitOutput(["rev-parse", "HEAD"], in: fixture.localURL),
            try gitOutput(["rev-parse", "refs/heads/main"], in: fixture.remoteURL)
        )
    }

    @MainActor
    private func makeEnvironment() -> RemoteOperationTestEnvironment {
        let contextProvider = RepositoryAIRemoteOperationContextProvider()
        let undoManager = GitUndoManager()
        let syncState = SyncState()
        let progress = RepositoryOperationProgress()
        let resolver = GitProviderCredentialResolver(
            accounts: [],
            tokenVault: RemoteOperationTokenVault()
        )
        return RemoteOperationTestEnvironment(
            contextProvider: contextProvider,
            undoManager: undoManager,
            executor: RepositoryAIRemoteOperationExecutor(
                contextProvider: contextProvider,
                credentialResolverProvider: { _ in resolver },
                undoManager: undoManager,
                syncState: syncState,
                operationProgress: progress
            )
        )
    }

    private func makeFixture() throws -> RemoteOperationFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "macgit-repository-ai-remote-\(UUID().uuidString)", directoryHint: .isDirectory)
        let seedURL = rootURL.appending(path: "seed", directoryHint: .isDirectory)
        let remoteURL = rootURL.appending(path: "remote.git", directoryHint: .isDirectory)
        let localURL = rootURL.appending(path: "local", directoryHint: .isDirectory)
        let peerURL = rootURL.appending(path: "peer", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: seedURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: seedURL)
        try configureIdentity(in: seedURL)
        try "base\n".write(to: seedURL.appending(path: "tracked.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "tracked.txt"], in: seedURL)
        try runGit(["commit", "-m", "initial"], in: seedURL)
        try runGit(["init", "--bare", remoteURL.path], in: rootURL)
        try runGit(["remote", "add", "origin", remoteURL.path], in: seedURL)
        try runGit(["push", "-u", "origin", "main"], in: seedURL)
        try runGit(["symbolic-ref", "HEAD", "refs/heads/main"], in: remoteURL)
        try runGit(["clone", remoteURL.path, localURL.path], in: rootURL)
        try runGit(["clone", remoteURL.path, peerURL.path], in: rootURL)
        try configureIdentity(in: localURL)
        try configureIdentity(in: peerURL)
        return RemoteOperationFixture(
            rootURL: rootURL,
            remoteURL: remoteURL,
            localURL: localURL,
            peerURL: peerURL
        )
    }

    private func addCommitAndPush(_ message: String, file: String, in repositoryURL: URL) throws {
        try addCommit(message, file: file, in: repositoryURL)
        try runGit(["push", "origin", "main"], in: repositoryURL)
    }

    private func addCommit(_ message: String, file: String, in repositoryURL: URL) throws {
        try message.write(to: repositoryURL.appending(path: file), atomically: true, encoding: .utf8)
        try runGit(["add", file], in: repositoryURL)
        try runGit(["commit", "-m", message], in: repositoryURL)
    }

    private func configureIdentity(in repositoryURL: URL) throws {
        try runGit(["config", "user.name", "Repository AI Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "repository-ai@example.com"], in: repositoryURL)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in repositoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        let output = String(data: standardOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let error = String(data: standardError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw GitError.commandFailed(error)
        }
        return output
    }

    private func gitOutput(_ arguments: [String], in repositoryURL: URL) throws -> String {
        try runGit(arguments, in: repositoryURL).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RemoteOperationFixture {
    let rootURL: URL
    let remoteURL: URL
    let localURL: URL
    let peerURL: URL
}

@MainActor
private struct RemoteOperationTestEnvironment {
    let contextProvider: RepositoryAIRemoteOperationContextProvider
    let undoManager: GitUndoManager
    let executor: RepositoryAIRemoteOperationExecutor
}

@MainActor
private final class RemoteOperationTokenVault: GitProviderTokenVault {
    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? { nil }
    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {}
    func deleteToken(for account: GitProviderAccount) throws {}
}
