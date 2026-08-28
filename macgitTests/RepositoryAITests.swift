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

final class RepositoryAITests: XCTestCase {
    func testCommitToolResolvesReferenceAndBuildsBoundedContext() async throws {
        let hash = String(repeating: "a", count: 40)
        let runner = RepositoryAIGitRunner(hash: hash)
        let service = GitStatusService(runner: runner)

        let result = try await service.execute(
            .commitChanges(reference: "HEAD"),
            in: URL(fileURLWithPath: "/tmp/repository-ai"),
            characterBudget: 3_000
        )

        XCTAssertEqual(result.toolName, "commit_changes")
        XCTAssertEqual(result.fingerprint, hash)
        XCTAssertEqual(result.title, "Commit aaaaaaaa")
        XCTAssertTrue(result.content.contains("Subject: Add repository AI"))
        XCTAssertTrue(result.content.contains("M\tmacgit/App.swift"))
        XCTAssertTrue(result.content.contains("+let repositoryAI = true"))
        XCTAssertLessThanOrEqual(result.content.count, 3_000)
    }

    func testCommitToolRejectsOptionLikeReferenceBeforeRunningGit() async {
        let runner = RepositoryAIGitRunner(hash: String(repeating: "b", count: 40))
        let service = GitStatusService(runner: runner)

        do {
            _ = try await service.execute(
                .commitChanges(reference: "--help"),
                in: URL(fileURLWithPath: "/tmp/repository-ai"),
                characterBudget: 3_000
            )
            XCTFail("Expected an invalid commit reference")
        } catch let error as RepositoryAIError {
            XCTAssertEqual(error, .invalidCommitReference)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let callCount = await runner.callCount()
        XCTAssertEqual(callCount, 0)
    }

    @MainActor
    func testControllerRoutesToolResultThroughSelectedProvider() async throws {
        let defaults = makeDefaults()
        let toolExecutor = StubRepositoryAIToolExecutor(currentFingerprint: "changes-1")
        let provider = StubRepositoryAIProvider()
        let controller = AIProviderController(
            registry: AIProviderRegistry(providers: [provider]),
            snapshotLoader: StubRepositoryAISnapshotLoader(),
            repositoryToolExecutor: toolExecutor,
            defaults: defaults
        )

        let response = try await controller.answerRepositoryQuestion(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main",
            question: "Review these changes",
            tool: .workingTreeChanges
        )

        XCTAssertEqual(response, "Reviewed working_tree_changes in example")
        let receivedTool = await toolExecutor.receivedTool()
        let receivedBudget = await toolExecutor.receivedBudget()
        XCTAssertEqual(receivedTool, .workingTreeChanges)
        XCTAssertEqual(receivedBudget, 4_000)
    }

    @MainActor
    func testControllerRejectsAnswerWhenRepositoryContextChanges() async throws {
        let toolExecutor = StubRepositoryAIToolExecutor(currentFingerprint: "changes-2")
        let controller = AIProviderController(
            registry: AIProviderRegistry(providers: [StubRepositoryAIProvider()]),
            snapshotLoader: StubRepositoryAISnapshotLoader(),
            repositoryToolExecutor: toolExecutor,
            defaults: makeDefaults()
        )

        do {
            _ = try await controller.answerRepositoryQuestion(
                repositoryURL: URL(fileURLWithPath: "/tmp/example"),
                branchName: "main",
                question: "Review these changes",
                tool: .workingTreeChanges
            )
            XCTFail("Expected stale context rejection")
        } catch let error as RepositoryAIError {
            XCTAssertEqual(error, .contextChanged)
        }
    }

    @MainActor
    private func makeDefaults() -> UserDefaults {
        let suiteName = "RepositoryAITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private actor RepositoryAIGitRunner: GitCommandRunning {
    private let hash: String
    private var calls = 0

    init(hash: String) {
        self.hash = hash
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        calls += 1
        if arguments.first == "rev-parse" {
            return hash
        }
        if arguments.contains("--name-status") {
            return "M\tmacgit/App.swift"
        }
        if arguments.contains("--numstat") {
            return "1\t0\tmacgit/App.swift"
        }
        if arguments.contains("--unified=3") {
            return "diff --git a/macgit/App.swift b/macgit/App.swift\n+let repositoryAI = true"
        }
        if arguments.contains(where: { $0.hasPrefix("--format=Commit:") }) {
            return "Commit: \(hash)\nAuthor: Test\nSubject: Add repository AI"
        }
        return ""
    }

    func callCount() -> Int {
        calls
    }
}

private struct StubRepositoryAIProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
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

    func availability() async -> AIProviderAvailability {
        .available
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "test: message", body: nil)
    }

    func generateRepositoryResponse(request: RepositoryAIRequest) async throws -> String {
        "Reviewed \(request.toolResult.toolName) in \(request.repositoryName)"
    }
}

private actor StubRepositoryAIToolExecutor: RepositoryAIToolExecuting {
    private let currentFingerprint: String
    private var tool: RepositoryAIToolCall?
    private var budget: Int?

    init(currentFingerprint: String) {
        self.currentFingerprint = currentFingerprint
    }

    func execute(
        _ tool: RepositoryAIToolCall,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> RepositoryAIToolResult {
        self.tool = tool
        budget = characterBudget
        return RepositoryAIToolResult(
            toolName: tool.name,
            title: "Working tree changes",
            fingerprint: "changes-1",
            content: "M\tmacgit/App.swift",
            isTruncated: false
        )
    }

    func fingerprint(
        for tool: RepositoryAIToolCall,
        in repositoryURL: URL
    ) async throws -> String {
        currentFingerprint
    }

    func receivedTool() -> RepositoryAIToolCall? {
        tool
    }

    func receivedBudget() -> Int? {
        budget
    }
}

private actor StubRepositoryAISnapshotLoader: CommitChangeSnapshotLoading {
    func commitChangeSnapshot(
        in repositoryURL: URL,
        source: CommitChangeSource,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        CommitChangeSnapshot(fingerprint: "unused", context: "", isTruncated: false)
    }

    func changesFingerprint(
        in repositoryURL: URL,
        source: CommitChangeSource
    ) async throws -> String {
        "unused"
    }
}
