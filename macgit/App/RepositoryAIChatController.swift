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

import Combine
import Foundation

@MainActor
final class RepositoryAIChatController: ObservableObject {
    @Published var draft = ""
    @Published var commitReferenceDraft = ""
    @Published private(set) var conversationTitle = "New conversation"
    @Published private(set) var messages: [RepositoryAIMessage] = []
    @Published private(set) var recentCommits: [RepositoryAICommitChoice] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isChoosingCommit = false
    @Published private(set) var isLoadingCommits = false

    private let repositoryURL: URL
    private let providerController: AIProviderController
    private let gitService: GitStatusService
    private var conversationSessionID = UUID().uuidString
    private var activeRequestTask: Task<Void, Never>?

    init(
        repositoryURL: URL,
        providerController: AIProviderController,
        gitService: GitStatusService = .shared
    ) {
        self.repositoryURL = repositoryURL
        self.providerController = providerController
        self.gitService = gitService
    }

    var canSubmit: Bool {
        !isRunning && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canExplainCommitReference: Bool {
        !isRunning
            && !isLoadingCommits
            && !commitReferenceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reviewChanges() async {
        await startRequest(
            "Review the current repository changes. Focus on concrete bugs, regressions, security issues, and missing tests.",
            mode: .agent,
            contextTitle: "Repository analysis",
            conversationTitle: "Review changes"
        )
    }

    func prepareCommitExplanation() async {
        guard !isRunning, !isLoadingCommits else { return }
        isChoosingCommit = true
        isLoadingCommits = true
        let commits = await gitService.recentCommits(limit: 10, in: repositoryURL)
        recentCommits = commits.map {
            RepositoryAICommitChoice(hash: $0.hash, subject: $0.message)
        }
        isLoadingCommits = false
    }

    func explainCommit(_ commit: RepositoryAICommitChoice) async {
        await explainCommit(reference: commit.hash, subject: commit.subject)
    }

    func explainCommitReference() async {
        await explainCommit(reference: commitReferenceDraft, subject: nil)
    }

    func cancelCommitSelection() {
        guard !isRunning, !isLoadingCommits else { return }
        isChoosingCommit = false
        commitReferenceDraft = ""
    }

    private func explainCommit(reference: String, subject: String?) async {
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else { return }

        isChoosingCommit = false
        commitReferenceDraft = ""
        await startRequest(
            "Explain what this commit changes, why it likely exists, and any behavior or risks a reviewer should understand.",
            mode: .fixedTool(.commitChanges(reference: normalizedReference)),
            contextTitle: "Commit \(normalizedReference)",
            conversationTitle: subject.map { "Explain \($0)" } ?? "Explain \(normalizedReference)"
        )
    }

    func submitDraft() async {
        let question = draft
        draft = ""
        await startRequest(
            question,
            mode: .agent,
            contextTitle: "Repository analysis"
        )
    }

    func startNewConversation() {
        guard !isRunning else { return }
        draft = ""
        commitReferenceDraft = ""
        messages.removeAll()
        recentCommits.removeAll()
        isChoosingCommit = false
        isLoadingCommits = false
        conversationTitle = "New conversation"
        conversationSessionID = UUID().uuidString
    }

    func cancelActiveRequest() {
        activeRequestTask?.cancel()
    }

    private func startRequest(
        _ question: String,
        mode: RepositoryAIRequestMode,
        contextTitle: String,
        conversationTitle preferredTitle: String? = nil
    ) async {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.ask(
                question,
                mode: mode,
                contextTitle: contextTitle,
                conversationTitle: preferredTitle
            )
        }
        activeRequestTask = task
        await task.value
        activeRequestTask = nil
    }

    private func ask(
        _ question: String,
        mode: RepositoryAIRequestMode,
        contextTitle: String,
        conversationTitle preferredTitle: String? = nil
    ) async {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isRunning else { return }

        if messages.isEmpty {
            conversationTitle = makeConversationTitle(from: preferredTitle ?? normalized)
        }
        messages.append(RepositoryAIMessage(
            role: .user,
            text: normalized,
            contextTitle: contextTitle
        ))
        isRunning = true
        defer { isRunning = false }

        do {
            let branch = await gitService.currentBranch(in: repositoryURL)
            switch mode {
            case .agent:
                let result = try await providerController.answerRepositoryQuestionWithAgent(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    conversation: messages
                )
                for toolResult in result.toolResults {
                    messages.append(RepositoryAIMessage(
                        role: .toolActivity,
                        text: toolResult.commandResult.displayCommand,
                        toolResult: toolResult
                    ))
                }
                messages.append(RepositoryAIMessage(role: .assistant, text: result.answer))
            case .fixedTool(let tool):
                let response = try await providerController.answerRepositoryQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    tool: tool,
                    sessionID: conversationSessionID
                )
                messages.append(RepositoryAIMessage(role: .assistant, text: response))
            }
        } catch is CancellationError {
            messages.append(RepositoryAIMessage(role: .assistant, text: "The AI request was cancelled."))
        } catch {
            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: error.localizedDescription
            ))
        }
    }

    private enum RepositoryAIRequestMode {
        case agent
        case fixedTool(RepositoryAIToolCall)
    }

    private func makeConversationTitle(from text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let title = words.prefix(5).joined(separator: " ")
        guard words.count > 5 else { return title }
        return "\(title)…"
    }
}
