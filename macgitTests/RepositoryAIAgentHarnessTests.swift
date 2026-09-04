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

final class RepositoryAIAgentHarnessTests: XCTestCase {
    func testHarnessExecutesStagedDiffBeforeReturningAnswer() async throws {
        let executor = StubRepositoryAIGitCommandExecutor()
        let harness = RepositoryAIAgentHarness(
            commandExecutor: executor,
            stateProvider: StaticRepositoryAIStateProvider()
        )

        let result = try await harness.answer(
            question: "Review staged files",
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main",
            provider: StagedReviewAgentProvider()
        )

        XCTAssertEqual(result.answer, "The staged diff updates App.swift.")
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].commandResult.succeeded)
        let arguments = await executor.recordedArguments()
        XCTAssertEqual(arguments, [["diff", "--cached", "--name-status", "--unified=3"]])
    }

    func testHarnessRejectsFinalAnswerWithoutGitEvidence() async {
        let harness = RepositoryAIAgentHarness(
            commandExecutor: StubRepositoryAIGitCommandExecutor(),
            stateProvider: StaticRepositoryAIStateProvider()
        )

        do {
            _ = try await harness.answer(
                question: "Review staged files",
                repositoryURL: URL(fileURLWithPath: "/tmp/example"),
                branchName: "main",
                provider: UngroundedRepositoryAIAgentProvider()
            )
            XCTFail("Expected ungrounded answer rejection")
        } catch let error as RepositoryAIAgentError {
            XCTAssertEqual(error, .noRepositoryEvidence)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHarnessRejectsAnswerWhenRepositoryChangesDuringAnalysis() async {
        let harness = RepositoryAIAgentHarness(
            commandExecutor: StubRepositoryAIGitCommandExecutor(),
            stateProvider: ChangingRepositoryAIStateProvider()
        )

        do {
            _ = try await harness.answer(
                question: "Review staged files",
                repositoryURL: URL(fileURLWithPath: "/tmp/example"),
                branchName: "main",
                provider: StagedReviewAgentProvider()
            )
            XCTFail("Expected stale repository rejection")
        } catch let error as RepositoryAIAgentError {
            XCTAssertEqual(error, .repositoryChanged)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHarnessAllowsTenGitQueriesByDefault() async throws {
        let executor = StubRepositoryAIGitCommandExecutor()
        let harness = RepositoryAIAgentHarness(
            commandExecutor: executor,
            stateProvider: StaticRepositoryAIStateProvider()
        )

        let result = try await harness.answer(
            question: "Review the repository",
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main",
            provider: TenQueryRepositoryAIAgentProvider()
        )

        XCTAssertEqual(result.answer, "Reviewed after ten Git queries.")
        XCTAssertEqual(result.toolResults.count, 10)
        let arguments = await executor.recordedArguments()
        XCTAssertEqual(arguments.count, 10)
    }

    func testHarnessReturnsQuickActionWithoutExecutingGit() async throws {
        let executor = StubRepositoryAIGitCommandExecutor()
        let harness = RepositoryAIAgentHarness(
            commandExecutor: executor,
            stateProvider: StaticRepositoryAIStateProvider()
        )

        let result = try await harness.answer(
            question: "review file",
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main",
            provider: QuickActionRepositoryAIAgentProvider(action: .reviewFile)
        )

        XCTAssertEqual(result.quickAction, .reviewFile)
        XCTAssertTrue(result.answer.isEmpty)
        XCTAssertTrue(result.toolResults.isEmpty)
        let arguments = await executor.recordedArguments()
        XCTAssertTrue(arguments.isEmpty)
    }

    func testHarnessReturnsValidatedMutationWithoutExecutingGit() async throws {
        let executor = StubRepositoryAIGitCommandExecutor()
        let harness = RepositoryAIAgentHarness(
            commandExecutor: executor,
            stateProvider: StaticRepositoryAIStateProvider(),
            mutationContextProvider: StaticRepositoryAIMutationContextProvider()
        )

        let result = try await harness.answer(
            question: "stage App.swift",
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main",
            provider: MutationRepositoryAIAgentProvider()
        )

        guard case .stageFiles(let paths) = result.mutation?.proposal else {
            return XCTFail("Expected a validated stage proposal")
        }
        XCTAssertEqual(paths.map(\.file.path), ["App.swift"])
        XCTAssertTrue(result.toolResults.isEmpty)
        let recordedArguments = await executor.recordedArguments()
        XCTAssertTrue(recordedArguments.isEmpty)
    }

    @MainActor
    func testSubmitDraftRoutesAgentReviewFileActionToFilePicker() async {
        let suiteName = "RepositoryAIAgentHarnessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let harness = RepositoryAIAgentHarness(
            commandExecutor: StubRepositoryAIGitCommandExecutor(),
            stateProvider: StaticRepositoryAIStateProvider()
        )
        let providerController = AIProviderController(
            registry: AIProviderRegistry(providers: [
                QuickActionRepositoryAIAgentProvider(action: .reviewFile),
            ]),
            snapshotLoader: StubRepositoryAICommitChangeSnapshotLoader(),
            repositoryAgentHarness: harness,
            defaults: defaults
        )
        let controller = RepositoryAIChatController(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            providerController: providerController
        )
        controller.draft = "review file"

        await controller.submitDraft()

        XCTAssertTrue(controller.isChoosingFile)
        XCTAssertEqual(controller.messages.count, 1)
        XCTAssertEqual(controller.messages.first?.text, "review file")
    }

    @MainActor
    func testControllerDoesNotExecuteBeforeConfirmationOrAfterCancellation() async {
        let suiteName = "RepositoryAIMutationControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let harness = RepositoryAIAgentHarness(
            commandExecutor: StubRepositoryAIGitCommandExecutor(),
            stateProvider: StaticRepositoryAIStateProvider(),
            mutationContextProvider: StaticRepositoryAIMutationContextProvider()
        )
        let providerController = AIProviderController(
            registry: AIProviderRegistry(providers: [MutationRepositoryAIAgentProvider()]),
            snapshotLoader: StubRepositoryAICommitChangeSnapshotLoader(),
            repositoryAgentHarness: harness,
            defaults: defaults
        )
        let mutationExecutor = RecordingRepositoryAIMutationExecutor()
        let controller = RepositoryAIChatController(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            providerController: providerController,
            mutationExecutor: mutationExecutor
        )
        controller.draft = "stage App.swift"

        await controller.submitDraft()

        XCTAssertNotNil(controller.pendingMutation)
        XCTAssertEqual(mutationExecutor.executionCount, 0)
        controller.cancelPendingMutation()
        XCTAssertNil(controller.pendingMutation)
        XCTAssertEqual(mutationExecutor.executionCount, 0)
        XCTAssertTrue(controller.messages.last?.text.hasPrefix("Cancelled") == true)
    }

    @MainActor
    func testControllerExecutesOnlyAfterExplicitConfirmation() async throws {
        let suiteName = "RepositoryAIMutationConfirmationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let harness = RepositoryAIAgentHarness(
            commandExecutor: StubRepositoryAIGitCommandExecutor(),
            stateProvider: StaticRepositoryAIStateProvider(),
            mutationContextProvider: StaticRepositoryAIMutationContextProvider()
        )
        let providerController = AIProviderController(
            registry: AIProviderRegistry(providers: [MutationRepositoryAIAgentProvider()]),
            snapshotLoader: StubRepositoryAICommitChangeSnapshotLoader(),
            repositoryAgentHarness: harness,
            defaults: defaults
        )
        let mutationExecutor = RecordingRepositoryAIMutationExecutor()
        let controller = RepositoryAIChatController(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            providerController: providerController,
            mutationExecutor: mutationExecutor
        )
        controller.draft = "stage App.swift"
        await controller.submitDraft()
        let pending = try XCTUnwrap(controller.pendingMutation)

        await controller.confirmPendingMutation(id: pending.id)

        XCTAssertEqual(mutationExecutor.executionCount, 1)
        XCTAssertNil(controller.pendingMutation)
        XCTAssertTrue(controller.messages.last?.text.hasPrefix("Succeeded") == true)
    }

    @MainActor
    func testExpiredApprovalDoesNotExecute() async throws {
        let suiteName = "RepositoryAIMutationExpirationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let providerController = AIProviderController(
            registry: AIProviderRegistry(providers: [MutationRepositoryAIAgentProvider()]),
            snapshotLoader: StubRepositoryAICommitChangeSnapshotLoader(),
            defaults: defaults
        )
        let mutationExecutor = RecordingRepositoryAIMutationExecutor()
        let controller = RepositoryAIChatController(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            providerController: providerController,
            mutationExecutor: mutationExecutor
        )
        let context = try await StaticRepositoryAIMutationContextProvider().context(
            in: URL(fileURLWithPath: "/tmp/example")
        )
        let path = try XCTUnwrap(context.stageablePaths.first)
        let validated = try RepositoryAIMutationPolicy.validate(
            .stageFiles(paths: [path]),
            context: context
        )
        let pending = PendingRepositoryAIMutation(
            validatedMutation: validated,
            conversationID: "expired",
            originatingMessageID: UUID(),
            providerID: providerController.selectedProviderID,
            createdAt: .now.addingTimeInterval(-10),
            lifetime: 1
        )
        controller.pendingMutation = pending

        await controller.confirmPendingMutation(id: pending.id)

        XCTAssertEqual(mutationExecutor.executionCount, 0)
        XCTAssertNil(controller.pendingMutation)
        XCTAssertTrue(controller.messages.last?.text.hasPrefix("Stale") == true)
    }
}

private struct StagedReviewAgentProvider: CommitMessageAIProvider {
    let descriptor = RepositoryAIAgentHarnessTestSupport.descriptor

    func availability() async -> AIProviderAvailability { .available }

    func generateCommitMessage(request: CommitMessageGenerationRequest) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "test: message", body: nil)
    }

    func generateRepositoryAgentTurn(request: RepositoryAIAgentRequest) async throws -> RepositoryAIAgentTurn {
        if request.isFirstTurn {
            return RepositoryAIAgentTurn(
                text: "",
                toolCalls: [RepositoryAIAgentToolCall(
                    id: "staged-diff",
                    name: "execute_git",
                    arguments: ["diff", "--cached", "--name-status", "--unified=3"]
                )]
            )
        }
        return RepositoryAIAgentTurn(text: "The staged diff updates App.swift.", toolCalls: [])
    }
}

private struct UngroundedRepositoryAIAgentProvider: CommitMessageAIProvider {
    let descriptor = RepositoryAIAgentHarnessTestSupport.descriptor

    func availability() async -> AIProviderAvailability { .available }

    func generateCommitMessage(request: CommitMessageGenerationRequest) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "test: message", body: nil)
    }

    func generateRepositoryAgentTurn(request: RepositoryAIAgentRequest) async throws -> RepositoryAIAgentTurn {
        RepositoryAIAgentTurn(text: "Ungrounded answer", toolCalls: [])
    }
}

private struct TenQueryRepositoryAIAgentProvider: CommitMessageAIProvider {
    let descriptor = RepositoryAIAgentHarnessTestSupport.descriptor

    func availability() async -> AIProviderAvailability { .available }

    func generateCommitMessage(request: CommitMessageGenerationRequest) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "test: message", body: nil)
    }

    func generateRepositoryAgentTurn(request: RepositoryAIAgentRequest) async throws -> RepositoryAIAgentTurn {
        let queryIndex = request.previousToolResults.count
        guard queryIndex < 10 else {
            return RepositoryAIAgentTurn(text: "Reviewed after ten Git queries.", toolCalls: [])
        }
        return RepositoryAIAgentTurn(
            text: "",
            toolCalls: [RepositoryAIAgentToolCall(
                id: "query-\(queryIndex)",
                name: "execute_git",
                arguments: ["status", "--short"]
            )]
        )
    }
}

private struct QuickActionRepositoryAIAgentProvider: CommitMessageAIProvider {
    let action: RepositoryAIQuickAction
    let descriptor = RepositoryAIAgentHarnessTestSupport.descriptor
    var supportsRepositoryAgent: Bool { true }

    func availability() async -> AIProviderAvailability { .available }

    func generateCommitMessage(request: CommitMessageGenerationRequest) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "test: message", body: nil)
    }

    func generateRepositoryAgentTurn(request: RepositoryAIAgentRequest) async throws -> RepositoryAIAgentTurn {
        RepositoryAIAgentTurn(
            text: "",
            toolCalls: [RepositoryAIAgentToolCall(
                id: "quick-action",
                name: action.rawValue,
                arguments: []
            )]
        )
    }
}

private struct MutationRepositoryAIAgentProvider: CommitMessageAIProvider {
    let descriptor = RepositoryAIAgentHarnessTestSupport.descriptor
    var supportsRepositoryAgent: Bool { true }

    func availability() async -> AIProviderAvailability { .available }

    func generateCommitMessage(request: CommitMessageGenerationRequest) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "test: message", body: nil)
    }

    func generateRepositoryAgentTurn(request: RepositoryAIAgentRequest) async throws -> RepositoryAIAgentTurn {
        RepositoryAIAgentTurn(
            text: "",
            toolCalls: [RepositoryAIAgentToolCall(
                id: "mutation",
                name: "stage_files",
                arguments: ["unstaged-1"]
            )]
        )
    }
}

private enum RepositoryAIAgentHarnessTestSupport {
    static let descriptor = AIProviderDescriptor(
        id: .appleIntelligence,
        displayName: "Test AI",
        systemImage: "sparkles",
        detail: "Test",
        dataProcessing: .onDevice,
        billing: .none,
        requiresProToConfigureAPIKey: false,
        defaultModel: nil,
        inputCharacterBudget: 4_000,
        isImplemented: true
    )
}

private actor StubRepositoryAIGitCommandExecutor: RepositoryAIGitCommandExecuting {
    private var calls = [[String]]()

    func execute(
        arguments: [String],
        in repositoryURL: URL,
        outputCharacterLimit: Int
    ) async throws -> RepositoryAIGitCommandResult {
        calls.append(arguments)
        return RepositoryAIGitCommandResult(
            displayCommand: "git " + arguments.joined(separator: " "),
            output: "M\tApp.swift",
            succeeded: true,
            isTruncated: false
        )
    }

    func recordedArguments() -> [[String]] {
        calls
    }
}

private actor StubRepositoryAICommitChangeSnapshotLoader: CommitChangeSnapshotLoading {
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

private struct StaticRepositoryAIStateProvider: RepositoryAIRepositoryStateProviding {
    func state(in repositoryURL: URL) async throws -> RepositoryAIRepositoryState {
        RepositoryAIRepositoryState(
            branch: "main",
            head: "head-1",
            stagedFingerprint: "index-1",
            workingTreeFingerprint: "worktree-1"
        )
    }
}

private struct StaticRepositoryAIMutationContextProvider: RepositoryAIMutationContextProviding {
    func context(in repositoryURL: URL) async throws -> RepositoryAIMutationPlanningContext {
        let file = StatusFile(path: "App.swift", status: .modified, originalPath: nil)
        let state = try await StaticRepositoryAIStateProvider().state(in: repositoryURL)
        return RepositoryAIMutationPlanningContext(
            repositoryIdentity: repositoryURL.standardizedFileURL.path,
            repositoryState: state,
            status: GitStatus(staged: [], unstaged: [file], untracked: []),
            paths: [RepositoryAIMutationPath(id: "unstaged-1", file: file, source: .unstaged)],
            localBranches: [RepositoryAIMutationRef(id: "branch-1", name: "main", commit: state.head)],
            startPoints: [RepositoryAIMutationRef(id: "start-head", name: "HEAD", commit: state.head)],
            conflictResolutions: [],
            stagedStatistics: RepositoryAIMutationStatistics(
                fileCount: 0,
                additions: 0,
                deletions: 0,
                binaryFileCount: 0
            ),
            author: "Test User <test@example.com>",
            signingEnabled: false,
            inProgressOperation: nil,
            branchesCheckedOutInOtherWorktrees: []
        )
    }
}

@MainActor
private final class RecordingRepositoryAIMutationExecutor: RepositoryAIMutationExecuting {
    private(set) var executionCount = 0

    func execute(
        _ mutation: RepositoryAIValidatedMutation,
        in repositoryURL: URL
    ) async throws -> RepositoryAIMutationExecutionResult {
        executionCount += 1
        return RepositoryAIMutationExecutionResult(summary: "Succeeded — test mutation executed.")
    }
}

private actor ChangingRepositoryAIStateProvider: RepositoryAIRepositoryStateProviding {
    private var requestCount = 0

    func state(in repositoryURL: URL) async throws -> RepositoryAIRepositoryState {
        requestCount += 1
        return RepositoryAIRepositoryState(
            branch: "main",
            head: "head-1",
            stagedFingerprint: requestCount == 1 ? "index-1" : "index-2",
            workingTreeFingerprint: "worktree-1"
        )
    }
}
