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

final class RepositoryAIMutationIntegrationTests: XCTestCase {
    @MainActor
    func testStageAndUnstageUseExistingServicesAndRegisterUndo() async throws {
        let repositoryURL = try makeRepository()
        let fileURL = repositoryURL.appending(path: "tracked.txt")
        try "changed\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let environment = makeEnvironment()

        var context = try await environment.contextProvider.context(in: repositoryURL)
        let stagePath = try XCTUnwrap(context.stageablePaths.first { $0.file.path == "tracked.txt" })
        let stageMutation = try RepositoryAIMutationPolicy.validate(
            .stageFiles(paths: [stagePath]),
            context: context
        )

        var status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.unstaged.contains { $0.path == "tracked.txt" })
        XCTAssertTrue(status.staged.isEmpty)

        _ = try await environment.executor.execute(stageMutation, in: repositoryURL)

        status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.staged.contains { $0.path == "tracked.txt" })
        XCTAssertEqual(environment.undoManager.undoStack.last?.label, "Stage tracked.txt")

        let undoExecutor = GitUndoExecutor()
        let stageEntry = try XCTUnwrap(environment.undoManager.popForUndo())
        try await undoExecutor.execute(stageEntry.undoOperation, in: repositoryURL)
        environment.undoManager.completeUndo(stageEntry)
        status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.unstaged.contains { $0.path == "tracked.txt" })

        let stageRedoEntry = try XCTUnwrap(environment.undoManager.popForRedo())
        try await undoExecutor.execute(stageRedoEntry.redoOperation, in: repositoryURL)
        environment.undoManager.completeRedo(stageRedoEntry)
        status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.staged.contains { $0.path == "tracked.txt" })

        context = try await environment.contextProvider.context(in: repositoryURL)
        let unstagePath = try XCTUnwrap(context.unstageablePaths.first { $0.file.path == "tracked.txt" })
        let unstageMutation = try RepositoryAIMutationPolicy.validate(
            .unstageFiles(paths: [unstagePath]),
            context: context
        )
        _ = try await environment.executor.execute(unstageMutation, in: repositoryURL)

        status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.unstaged.contains { $0.path == "tracked.txt" })
        XCTAssertTrue(status.staged.isEmpty)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "changed\n")
        XCTAssertEqual(environment.undoManager.undoStack.last?.label, "Unstage tracked.txt")

        let unstageEntry = try XCTUnwrap(environment.undoManager.popForUndo())
        try await undoExecutor.execute(unstageEntry.undoOperation, in: repositoryURL)
        environment.undoManager.completeUndo(unstageEntry)
        status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.staged.contains { $0.path == "tracked.txt" })

        let unstageRedoEntry = try XCTUnwrap(environment.undoManager.popForRedo())
        try await undoExecutor.execute(unstageRedoEntry.redoOperation, in: repositoryURL)
        environment.undoManager.completeRedo(unstageRedoEntry)
        status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.unstaged.contains { $0.path == "tracked.txt" })
        XCTAssertTrue(status.staged.isEmpty)
    }

    @MainActor
    func testCommitAndCreateBranchRegisterExpectedUndoEntries() async throws {
        let repositoryURL = try makeRepository()
        try "changed\n".write(
            to: repositoryURL.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], in: repositoryURL)
        let environment = makeEnvironment()
        var context = try await environment.contextProvider.context(in: repositoryURL)
        let oldHead = context.repositoryState.head
        let commit = try RepositoryAIMutationPolicy.validate(
            .createCommit(message: "test: repository ai commit"),
            context: context
        )

        _ = try await environment.executor.execute(commit, in: repositoryURL)

        let newHead = try runGit(["rev-parse", "HEAD"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(newHead, oldHead)
        XCTAssertEqual(environment.undoManager.undoStack.last?.label, "Commit")

        let undoExecutor = GitUndoExecutor()
        let commitEntry = try XCTUnwrap(environment.undoManager.popForUndo())
        try await undoExecutor.execute(commitEntry.undoOperation, in: repositoryURL)
        environment.undoManager.completeUndo(commitEntry)
        XCTAssertEqual(
            try runGit(["rev-parse", "HEAD"], in: repositoryURL)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            oldHead
        )

        let commitRedoEntry = try XCTUnwrap(environment.undoManager.popForRedo())
        try await undoExecutor.execute(commitRedoEntry.redoOperation, in: repositoryURL)
        environment.undoManager.completeRedo(commitRedoEntry)
        XCTAssertNotEqual(
            try runGit(["rev-parse", "HEAD"], in: repositoryURL)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            oldHead
        )

        context = try await environment.contextProvider.context(in: repositoryURL)
        let startPoint = try XCTUnwrap(context.startPoint(id: "start-head"))
        let branch = try RepositoryAIMutationPolicy.validate(
            .createBranch(name: "repository-ai-branch", startPoint: startPoint),
            context: context
        )
        _ = try await environment.executor.execute(branch, in: repositoryURL)

        let branches = await GitStatusService.shared.localBranches(in: repositoryURL)
        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        XCTAssertTrue(branches.contains("repository-ai-branch"))
        XCTAssertEqual(environment.undoManager.undoStack.last?.label, "Create branch repository-ai-branch")
        XCTAssertEqual(currentBranch, "main")

        let branchEntry = try XCTUnwrap(environment.undoManager.popForUndo())
        try await undoExecutor.execute(branchEntry.undoOperation, in: repositoryURL)
        environment.undoManager.completeUndo(branchEntry)
        let branchesAfterUndo = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertFalse(branchesAfterUndo.contains("repository-ai-branch"))

        let branchRedoEntry = try XCTUnwrap(environment.undoManager.popForRedo())
        try await undoExecutor.execute(branchRedoEntry.redoOperation, in: repositoryURL)
        environment.undoManager.completeRedo(branchRedoEntry)
        let branchesAfterRedo = await GitStatusService.shared.localBranches(in: repositoryURL)
        XCTAssertTrue(branchesAfterRedo.contains("repository-ai-branch"))
    }

    @MainActor
    func testCleanLocalCheckoutRegistersUndo() async throws {
        let repositoryURL = try makeRepository()
        try runGit(["branch", "feature"], in: repositoryURL)
        let environment = makeEnvironment()
        let context = try await environment.contextProvider.context(in: repositoryURL)
        let target = try XCTUnwrap(context.localBranches.first { $0.name == "feature" })
        let checkout = try RepositoryAIMutationPolicy.validate(
            .checkoutBranch(target: target),
            context: context
        )

        _ = try await environment.executor.execute(checkout, in: repositoryURL)

        let currentBranch = await GitStatusService.shared.currentBranch(in: repositoryURL)
        XCTAssertEqual(currentBranch, "feature")
        XCTAssertEqual(environment.undoManager.undoStack.last?.label, "Checkout feature")

        let undoExecutor = GitUndoExecutor()
        let checkoutEntry = try XCTUnwrap(environment.undoManager.popForUndo())
        try await undoExecutor.execute(checkoutEntry.undoOperation, in: repositoryURL)
        environment.undoManager.completeUndo(checkoutEntry)
        let branchAfterUndo = await GitStatusService.shared.currentBranch(in: repositoryURL)
        XCTAssertEqual(branchAfterUndo, "main")

        let checkoutRedoEntry = try XCTUnwrap(environment.undoManager.popForRedo())
        try await undoExecutor.execute(checkoutRedoEntry.redoOperation, in: repositoryURL)
        environment.undoManager.completeRedo(checkoutRedoEntry)
        let branchAfterRedo = await GitStatusService.shared.currentBranch(in: repositoryURL)
        XCTAssertEqual(branchAfterRedo, "feature")
    }

    @MainActor
    func testStaleFingerprintPreventsExecutionAndUndoRegistration() async throws {
        let repositoryURL = try makeRepository()
        let fileURL = repositoryURL.appending(path: "tracked.txt")
        try "first change\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let environment = makeEnvironment()
        let context = try await environment.contextProvider.context(in: repositoryURL)
        let path = try XCTUnwrap(context.stageablePaths.first { $0.file.path == "tracked.txt" })
        let mutation = try RepositoryAIMutationPolicy.validate(
            .stageFiles(paths: [path]),
            context: context
        )
        try "different change\n".write(to: fileURL, atomically: true, encoding: .utf8)

        do {
            _ = try await environment.executor.execute(mutation, in: repositoryURL)
            XCTFail("Expected a stale proposal")
        } catch let error as RepositoryAIMutationError {
            guard case .stale = error else { return XCTFail("Expected stale, got \(error)") }
        }

        let status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.staged.isEmpty)
        XCTAssertTrue(environment.undoManager.undoStack.isEmpty)
    }

    @MainActor
    func testCommitAllCoordinatorStagesEverythingBeforeReturningCommitConfirmation() async throws {
        let repositoryURL = try makeRepository()
        try "changed\n".write(
            to: repositoryURL.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "new\n".write(
            to: repositoryURL.appending(path: "new.txt"),
            atomically: true,
            encoding: .utf8
        )
        let environment = makeEnvironment()
        let suiteName = "RepositoryAICommitAllIntegrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let providerController = AIProviderController(
            registry: AIProviderRegistry(providers: [CommitAllMessageProvider()]),
            snapshotLoader: GitStatusService.shared,
            defaults: defaults
        )
        let coordinator = RepositoryAICommitAllCoordinator(
            providerController: providerController,
            contextProvider: environment.contextProvider,
            mutationExecutor: environment.executor
        )
        let oldHead = try runGit(["rev-parse", "HEAD"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let preparation = try await coordinator.prepare(in: repositoryURL)

        var status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertEqual(Set(status.staged.map(\.path)), ["new.txt", "tracked.txt"])
        XCTAssertTrue(status.unstaged.isEmpty)
        XCTAssertTrue(status.untracked.isEmpty)
        XCTAssertEqual(environment.undoManager.undoStack.last?.label, "Stage 2 files")
        XCTAssertEqual(
            try runGit(["rev-parse", "HEAD"], in: repositoryURL)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            oldHead
        )
        guard case .createCommit(let message) = preparation.commitMutation.proposal else {
            return XCTFail("Expected a final commit proposal")
        }
        XCTAssertEqual(message, "test: commit all changes")
        XCTAssertTrue(preparation.commitMutation.preview.warning?.contains("Cancelling leaves the changes staged") == true)

        _ = try await environment.executor.execute(preparation.commitMutation, in: repositoryURL)

        let newHead = try runGit(["rev-parse", "HEAD"], in: repositoryURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(newHead, oldHead)
        status = try await GitStatusService.shared.status(for: repositoryURL)
        XCTAssertTrue(status.isEmpty)
        XCTAssertEqual(environment.undoManager.undoStack.last?.label, "Commit")
    }

    @MainActor
    private func makeEnvironment() -> MutationTestEnvironment {
        let contextProvider = RepositoryAIMutationContextProvider()
        let undoManager = GitUndoManager()
        let syncState = SyncState()
        let progress = RepositoryOperationProgress()
        return MutationTestEnvironment(
            contextProvider: contextProvider,
            undoManager: undoManager,
            executor: RepositoryAIMutationExecutor(
                contextProvider: contextProvider,
                undoManager: undoManager,
                syncState: syncState,
                operationProgress: progress
            )
        )
    }

    private func makeRepository() throws -> URL {
        let repositoryURL = FileManager.default.temporaryDirectory
            .appending(path: "macgit-repository-ai-mutation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repositoryURL)
        try runGit(["config", "user.name", "Repository AI Tests"], in: repositoryURL)
        try runGit(["config", "user.email", "repository-ai@example.com"], in: repositoryURL)
        try "base\n".write(
            to: repositoryURL.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "tracked.txt"], in: repositoryURL)
        try runGit(["commit", "-m", "initial"], in: repositoryURL)
        return repositoryURL
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
        let output = String(
            data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            let error = String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "git failed"
            throw GitError.commandFailed(error)
        }
        return output
    }
}

@MainActor
private struct MutationTestEnvironment {
    let contextProvider: RepositoryAIMutationContextProvider
    let undoManager: GitUndoManager
    let executor: RepositoryAIMutationExecutor
}

private struct CommitAllMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .appleIntelligence,
        displayName: "Commit All Test AI",
        systemImage: "sparkles",
        detail: "Test",
        dataProcessing: .onDevice,
        billing: .none,
        requiresProToConfigureAPIKey: false,
        defaultModel: nil,
        inputCharacterBudget: 20_000,
        isImplemented: true
    )

    func availability() async -> AIProviderAvailability { .available }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "test: commit all changes", body: nil)
    }
}
