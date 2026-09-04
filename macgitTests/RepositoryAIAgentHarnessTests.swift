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
