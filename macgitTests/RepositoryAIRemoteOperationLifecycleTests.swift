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

final class RepositoryAIRemoteOperationLifecycleTests: XCTestCase {
    func testHarnessReturnsRemoteProposalWithoutExecutingGit() async throws {
        let commandExecutor = RemoteLifecycleGitCommandExecutor()
        let harness = RepositoryAIAgentHarness(
            commandExecutor: commandExecutor,
            stateProvider: RemoteLifecycleStateProvider(),
            remoteOperationContextProvider: RemoteLifecycleContextProvider()
        )

        let result = try await harness.answer(
            question: "fetch origin",
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main",
            provider: RemoteLifecycleProvider(toolName: "fetch_remote", arguments: ["remote-1"])
        )

        XCTAssertEqual(result.remoteOperation?.operation, .fetch(remoteID: "remote-1"))
        XCTAssertTrue(result.toolResults.isEmpty)
        let executionCount = await commandExecutor.executionCount()
        XCTAssertEqual(executionCount, 0)
    }

    @MainActor
    func testControllerDoesNotExecuteBeforeConfirmationOrAfterDenial() async throws {
        let controller = makeController(
            provider: RemoteLifecycleProvider(toolName: "fetch_remote", arguments: ["remote-1"])
        )
        let recorder = RemoteLifecycleExecutionRecorder()
        controller.draft = "fetch origin"

        await controller.submitDraft()

        XCTAssertNotNil(controller.pendingRemoteOperation)
        XCTAssertEqual(recorder.executionCount, 0)
        controller.cancelPendingRemoteOperation()
        XCTAssertNil(controller.pendingRemoteOperation)
        XCTAssertEqual(recorder.executionCount, 0)
        XCTAssertTrue(controller.messages.last?.text.hasPrefix("Cancelled") == true)

        let deniedController = makeController(provider: RemoteLifecycleProvider(
            toolName: RepositoryAIRemoteOperationProposalDecoder.unsupportedToolName,
            arguments: ["Force push is outside the supported remote-operation policy."]
        ))
        deniedController.draft = "force push main"
        await deniedController.submitDraft()
        XCTAssertNil(deniedController.pendingRemoteOperation)
        XCTAssertTrue(deniedController.messages.last?.text.hasPrefix("Rejected") == true)
    }

    @MainActor
    func testCredentialSelectionCancellationProducesDeterministicOutcome() async throws {
        let controller = makeController(
            provider: RemoteLifecycleProvider(toolName: "fetch_remote", arguments: ["remote-1"])
        )
        controller.draft = "fetch origin"
        await controller.submitDraft()
        let pending = try XCTUnwrap(controller.pendingRemoteOperation)

        await controller.confirmPendingRemoteOperation(id: pending.id) { _ in
            throw RepositoryAIRemoteOperationError.cancelled("No provider account was selected.")
        }

        XCTAssertNil(controller.pendingRemoteOperation)
        XCTAssertTrue(controller.messages.last?.text.hasPrefix("Cancelled") == true)
    }

    @MainActor
    private func makeController(
        provider: RemoteLifecycleProvider
    ) -> RepositoryAIChatController {
        let suiteName = "RepositoryAIRemoteLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let harness = RepositoryAIAgentHarness(
            commandExecutor: RemoteLifecycleGitCommandExecutor(),
            stateProvider: RemoteLifecycleStateProvider(),
            remoteOperationContextProvider: RemoteLifecycleContextProvider()
        )
        let providerController = AIProviderController(
            registry: AIProviderRegistry(providers: [provider]),
            snapshotLoader: RemoteLifecycleSnapshotLoader(),
            repositoryAgentHarness: harness,
            defaults: defaults
        )
        return RepositoryAIChatController(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            providerController: providerController,
            remoteOperationContextProvider: RemoteLifecycleContextProvider()
        )
    }
}

private struct RemoteLifecycleProvider: CommitMessageAIProvider {
    let toolName: String
    let arguments: [String]
    let descriptor = AIProviderDescriptor(
        id: .appleIntelligence,
        displayName: "Remote Lifecycle AI",
        systemImage: "sparkles",
        detail: "Test",
        dataProcessing: .onDevice,
        billing: .none,
        requiresProToConfigureAPIKey: false,
        defaultModel: nil,
        inputCharacterBudget: 4_000,
        isImplemented: true
    )
    var supportsRepositoryAgent: Bool { true }

    func availability() async -> AIProviderAvailability { .available }

    func generateCommitMessage(request: CommitMessageGenerationRequest) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "test: message", body: nil)
    }

    func generateRepositoryAgentTurn(request: RepositoryAIAgentRequest) async throws -> RepositoryAIAgentTurn {
        RepositoryAIAgentTurn(
            text: "",
            toolCalls: [RepositoryAIAgentToolCall(
                id: "remote-operation",
                name: toolName,
                arguments: arguments
            )]
        )
    }
}

private actor RemoteLifecycleGitCommandExecutor: RepositoryAIGitCommandExecuting {
    private var count = 0

    func execute(
        arguments: [String],
        in repositoryURL: URL,
        outputCharacterLimit: Int
    ) async throws -> RepositoryAIGitCommandResult {
        count += 1
        return RepositoryAIGitCommandResult(
            displayCommand: "git status --short",
            output: "",
            succeeded: true,
            isTruncated: false
        )
    }

    func executionCount() -> Int { count }
}

private struct RemoteLifecycleStateProvider: RepositoryAIRepositoryStateProviding {
    func state(in repositoryURL: URL) async throws -> RepositoryAIRepositoryState {
        RemoteLifecycleContextProvider.state
    }
}

private struct RemoteLifecycleContextProvider: RepositoryAIRemoteOperationContextProviding {
    static let state = RepositoryAIRepositoryState(
        branch: "main",
        head: String(repeating: "a", count: 40),
        stagedFingerprint: "index-1",
        workingTreeFingerprint: "working-1"
    )

    func context(in repositoryURL: URL) async throws -> RepositoryAIRemoteOperationPlanningContext {
        RepositoryAIRemoteOperationPlanningContext(
            repositoryIdentity: repositoryURL.standardizedFileURL.path,
            repositoryState: Self.state,
            remotes: [RepositoryAIRemoteManifest(
                id: "remote-1",
                name: "origin",
                identityFingerprint: "remote-1",
                trackingRefsFingerprint: "tracking-1"
            )],
            currentBranch: nil,
            inProgressOperation: nil,
            isWorkingTreeClean: true
        )
    }
}

private actor RemoteLifecycleSnapshotLoader: CommitChangeSnapshotLoading {
    func commitChangeSnapshot(
        in repositoryURL: URL,
        source: CommitChangeSource,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        CommitChangeSnapshot(fingerprint: "tree-1", context: "", isTruncated: false)
    }

    func changesFingerprint(
        in repositoryURL: URL,
        source: CommitChangeSource
    ) async throws -> String {
        "tree-1"
    }
}

@MainActor
private final class RemoteLifecycleExecutionRecorder {
    private(set) var executionCount = 0
}
