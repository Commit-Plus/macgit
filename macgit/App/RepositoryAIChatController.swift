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
    @Published var comparisonBaseDraft = ""
    @Published var comparisonHeadDraft = ""
    @Published var pullRequestNumberDraft = ""
    @Published private(set) var conversationTitle = "New conversation"
    @Published private(set) var messages: [RepositoryAIMessage] = []
    @Published private(set) var recentCommits: [RepositoryAICommitChoice] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isChoosingCommit = false
    @Published private(set) var isChoosingFile = false
    @Published private(set) var isChoosingComparison = false
    @Published private(set) var isChoosingPullRequest = false
    @Published private(set) var isLoadingCommits = false
    @Published private(set) var isLoadingFiles = false
    @Published private(set) var changedFiles: [RepositoryAIFileReference] = []
    @Published private(set) var streamingRevision = 0

    private let repositoryURL: URL
    private let providerController: AIProviderController
    private let gitService: GitStatusService
    private let pullRequestContextLoader: ((Int?, URL) async throws -> RepositoryAIPullRequestContext)?
    private let pullRequestFingerprintLoader: ((Int, URL) async throws -> String)?
    private var conversationSessionID = UUID().uuidString
    private var activeRequestTask: Task<Void, Never>?
    private var pendingQuickAction: (action: RepositoryAIQuickAction, question: String)?

    init(
        repositoryURL: URL,
        providerController: AIProviderController,
        gitService: GitStatusService = .shared,
        pullRequestContextLoader: ((Int?, URL) async throws -> RepositoryAIPullRequestContext)? = nil,
        pullRequestFingerprintLoader: ((Int, URL) async throws -> String)? = nil
    ) {
        self.repositoryURL = repositoryURL
        self.providerController = providerController
        self.gitService = gitService
        self.pullRequestContextLoader = pullRequestContextLoader
        self.pullRequestFingerprintLoader = pullRequestFingerprintLoader
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
        dismissSelection()
        await startRequest(
            "Review the current repository changes. Focus on concrete bugs, regressions, security issues, and missing tests.",
            mode: .fixedTool(.workingTreeChanges),
            contextTitle: "Repository analysis",
            conversationTitle: "Review changes"
        )
    }

    func prepareCommitExplanation() async {
        guard !isRunning, !isLoadingCommits else { return }
        dismissSelection()
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
        pendingQuickAction = nil
        isChoosingCommit = false
        commitReferenceDraft = ""
    }

    func prepareFileReview() async {
        guard !isRunning, !isLoadingFiles else { return }
        dismissSelection()
        isChoosingFile = true
        isLoadingFiles = true
        changedFiles = (try? await gitService.listChangedFiles(in: repositoryURL)) ?? []
        isLoadingFiles = false
    }

    func reviewFile(_ reference: RepositoryAIFileReference, includeDiff: Bool = true) async {
        guard !isRunning else { return }
        let pendingQuestion = pendingQuickAction?.action == .reviewFile
            ? pendingQuickAction?.question
            : nil
        dismissSelection()
        await startRequest(
            pendingQuestion ?? (includeDiff
                ? "Review this file diff. Focus on concrete bugs, regressions, security issues, and missing tests."
                : "Explain this selected file context, including behavior and risks."),
            mode: .file(reference, includeDiff: includeDiff),
            contextTitle: reference.displayLabel,
            conversationTitle: "Review \(reference.path)",
            shouldAppendUserMessage: pendingQuestion == nil
        )
    }

    func cancelFileSelection() {
        guard !isRunning, !isLoadingFiles else { return }
        pendingQuickAction = nil
        isChoosingFile = false
        changedFiles.removeAll()
    }

    func prepareRefComparison() {
        guard !isRunning else { return }
        dismissSelection()
        if comparisonHeadDraft.isEmpty { comparisonHeadDraft = "HEAD" }
        isChoosingComparison = true
    }

    func compareRefs() async {
        guard !isRunning else { return }
        guard let base = RepositoryAIRef(comparisonBaseDraft),
              let head = RepositoryAIRef(comparisonHeadDraft) else {
            messages.append(RepositoryAIMessage(role: .assistant, text: RepositoryAIError.invalidRefReference.localizedDescription))
            return
        }
        let pendingQuestion = pendingQuickAction?.action == .compareRefs
            ? pendingQuickAction?.question
            : nil
        dismissSelection()
        await startRequest(
            pendingQuestion
                ?? "Compare these refs as a review. Explain meaningful behavior changes, risks, and missing tests.",
            mode: .comparison(base, head),
            contextTitle: "Compare \(base.name) → \(head.name)",
            conversationTitle: "Compare \(base.name) → \(head.name)",
            shouldAppendUserMessage: pendingQuestion == nil
        )
    }

    func cancelRefComparison() {
        guard !isRunning else { return }
        pendingQuickAction = nil
        isChoosingComparison = false
    }

    func preparePullRequestAnalysis() {
        guard !isRunning else { return }
        dismissSelection()
        isChoosingPullRequest = true
    }

    func analyzePullRequest() async {
        guard !isRunning, pullRequestContextLoader != nil, pullRequestFingerprintLoader != nil else { return }
        let number = Int(pullRequestNumberDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        guard number == nil || number! > 0 else {
            messages.append(RepositoryAIMessage(role: .assistant, text: "Enter a positive pull request number."))
            return
        }
        let pendingQuestion = pendingQuickAction?.action == .analyzePullRequest
            ? pendingQuickAction?.question
            : nil
        dismissSelection()
        let label = number.map { "Pull request #\($0)" } ?? "Selected pull request"
        await startRequest(
            pendingQuestion
                ?? "Analyze this pull request. Focus on concrete behavior changes, review risks, and missing tests.",
            mode: .pullRequest(number),
            contextTitle: label,
            conversationTitle: label,
            shouldAppendUserMessage: pendingQuestion == nil
        )
    }

    func cancelPullRequestAnalysis() {
        guard !isRunning else { return }
        pendingQuickAction = nil
        isChoosingPullRequest = false
    }

    private func explainCommit(reference: String, subject: String?) async {
        let normalizedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReference.isEmpty else { return }

        let pendingQuestion = pendingQuickAction?.action == .explainCommit
            ? pendingQuickAction?.question
            : nil
        dismissSelection()
        await startRequest(
            pendingQuestion
                ?? "Explain what this commit changes, why it likely exists, and any behavior or risks a reviewer should understand.",
            mode: .fixedTool(.commitChanges(reference: normalizedReference)),
            contextTitle: "Commit \(normalizedReference)",
            conversationTitle: subject.map { "Explain \($0)" } ?? "Explain \(normalizedReference)",
            shouldAppendUserMessage: pendingQuestion == nil
        )
    }

    func submitDraft() async {
        let question = draft
        draft = ""
        dismissSelection()
        await startRequest(
            question,
            mode: .agent,
            contextTitle: "Repository analysis"
        )
    }

    func startNewConversation() {
        guard !isRunning else { return }
        draft = ""
        messages.removeAll()
        dismissSelection()
        conversationTitle = "New conversation"
        conversationSessionID = UUID().uuidString
    }

    func cancelActiveRequest() {
        activeRequestTask?.cancel()
    }

    private func dismissSelection() {
        pendingQuickAction = nil
        commitReferenceDraft = ""
        recentCommits.removeAll()
        isChoosingCommit = false
        isChoosingFile = false
        isChoosingComparison = false
        isChoosingPullRequest = false
        isLoadingCommits = false
        isLoadingFiles = false
        changedFiles.removeAll()
    }

    private func startRequest(
        _ question: String,
        mode: RepositoryAIRequestMode,
        contextTitle: String,
        conversationTitle preferredTitle: String? = nil,
        shouldAppendUserMessage: Bool = true
    ) async {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.ask(
                question,
                mode: mode,
                contextTitle: contextTitle,
                conversationTitle: preferredTitle,
                shouldAppendUserMessage: shouldAppendUserMessage
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
        conversationTitle preferredTitle: String? = nil,
        shouldAppendUserMessage: Bool
    ) async {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isRunning else { return }

        if messages.isEmpty {
            conversationTitle = makeConversationTitle(from: preferredTitle ?? normalized)
        }
        if shouldAppendUserMessage {
            messages.append(RepositoryAIMessage(
                role: .user,
                text: normalized,
                contextTitle: contextTitle
            ))
        }
        isRunning = true
        defer { isRunning = false }

        var streamingMessageID: UUID?
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
                if let quickAction = result.quickAction {
                    try await handleQuickAction(
                        quickAction,
                        question: normalized,
                        branch: branch,
                        streamingMessageID: &streamingMessageID
                    )
                } else {
                    for toolResult in result.toolResults {
                        messages.append(RepositoryAIMessage(
                            role: .toolActivity,
                            text: toolResult.commandResult.displayCommand,
                            toolResult: toolResult
                        ))
                    }
                    messages.append(RepositoryAIMessage(role: .assistant, text: result.answer))
                }
            case .fixedTool(let tool):
                let messageID = beginStreamingAssistant()
                streamingMessageID = messageID
                let response = try await providerController.answerRepositoryQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    tool: tool,
                    sessionID: conversationSessionID,
                    onTextDelta: { [weak self] delta in
                        await self?.appendStreamingDelta(delta, to: messageID)
                    }
                )
                completeStreamingAssistant(messageID, with: response)
                streamingMessageID = nil
            case .file(let reference, let includeDiff):
                let response = try await providerController.answerRepositoryFileQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    reference: reference,
                    includeDiff: includeDiff,
                    sessionID: conversationSessionID
                )
                messages.append(RepositoryAIMessage(
                    role: .assistant,
                    text: response.answer.text,
                    citations: response.answer.citations,
                    evidenceManifest: response.manifest
                ))
            case .comparison(let base, let head):
                let budget = providerController.selectedDescriptor.inputCharacterBudget
                let comparison = try await gitService.compareRefs(
                    base: base,
                    head: head,
                    in: repositoryURL,
                    characterBudget: budget
                )
                let messageID = beginStreamingAssistant()
                streamingMessageID = messageID
                let response = try await providerController.answerRepositoryAnalysisQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    result: comparison.toolResult(characterBudget: budget),
                    currentFingerprint: { [gitService, repositoryURL] in
                        try await gitService.currentComparisonFingerprint(base: base, head: head, in: repositoryURL)
                    },
                    sessionID: conversationSessionID,
                    onTextDelta: { [weak self] delta in
                        await self?.appendStreamingDelta(delta, to: messageID)
                    }
                )
                completeStreamingAssistant(messageID, with: response)
                streamingMessageID = nil
            case .pullRequest(let number):
                guard let pullRequestContextLoader, let pullRequestFingerprintLoader else {
                    throw RepositoryAIError.noRepositoryData("an authenticated pull request for the current repository")
                }
                let context = try await pullRequestContextLoader(number, repositoryURL)
                let messageID = beginStreamingAssistant()
                streamingMessageID = messageID
                let response = try await providerController.answerRepositoryAnalysisQuestion(
                    repositoryURL: repositoryURL,
                    branchName: branch,
                    question: normalized,
                    result: context.toolResult(characterBudget: providerController.selectedDescriptor.inputCharacterBudget),
                    currentFingerprint: {
                        try await pullRequestFingerprintLoader(context.detail.summary.number, self.repositoryURL)
                    },
                    sessionID: conversationSessionID,
                    onTextDelta: { [weak self] delta in
                        await self?.appendStreamingDelta(delta, to: messageID)
                    }
                )
                completeStreamingAssistant(messageID, with: response)
                streamingMessageID = nil
            }
        } catch is CancellationError {
            removeStreamingAssistant(streamingMessageID)
            messages.append(RepositoryAIMessage(role: .assistant, text: "The AI request was cancelled."))
        } catch {
            removeStreamingAssistant(streamingMessageID)
            messages.append(RepositoryAIMessage(
                role: .assistant,
                text: error.localizedDescription
            ))
        }
    }

    private func beginStreamingAssistant() -> UUID {
        let message = RepositoryAIMessage(role: .assistant, text: "Generating analysis…")
        messages.append(message)
        return message.id
    }

    private func appendStreamingDelta(_ delta: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        let existingText = message.text == "Generating analysis…" ? "" : message.text
        messages[index] = RepositoryAIMessage(
            id: message.id,
            role: message.role,
            text: existingText + delta,
            contextTitle: message.contextTitle,
            toolResult: message.toolResult,
            citations: message.citations,
            evidenceManifest: message.evidenceManifest
        )
        streamingRevision &+= 1
    }

    private func completeStreamingAssistant(_ id: UUID, with answer: RepositoryAIAnswer) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        let truncationNotice = answer.isTruncated
            ? "\n\n> The provider reached its output limit. Ask “continue” to finish this analysis."
            : ""
        messages[index] = RepositoryAIMessage(
            id: message.id,
            role: message.role,
            text: answer.text + truncationNotice,
            contextTitle: message.contextTitle,
            toolResult: message.toolResult,
            citations: message.citations,
            evidenceManifest: message.evidenceManifest
        )
        streamingRevision &+= 1
    }

    private func removeStreamingAssistant(_ id: UUID?) {
        guard let id else { return }
        messages.removeAll { $0.id == id }
    }

    private func handleQuickAction(
        _ action: RepositoryAIQuickAction,
        question: String,
        branch: String?,
        streamingMessageID: inout UUID?
    ) async throws {
        switch action {
        case .reviewChanges:
            let messageID = beginStreamingAssistant()
            streamingMessageID = messageID
            let response = try await providerController.answerRepositoryQuestion(
                repositoryURL: repositoryURL,
                branchName: branch,
                question: question,
                tool: .workingTreeChanges,
                sessionID: conversationSessionID,
                onTextDelta: { [weak self] delta in
                    await self?.appendStreamingDelta(delta, to: messageID)
                }
            )
            completeStreamingAssistant(messageID, with: response)
            streamingMessageID = nil
        case .explainCommit:
            pendingQuickAction = (action, question)
            isChoosingCommit = true
            isLoadingCommits = true
            let commits = await gitService.recentCommits(limit: 10, in: repositoryURL)
            recentCommits = commits.map {
                RepositoryAICommitChoice(hash: $0.hash, subject: $0.message)
            }
            isLoadingCommits = false
        case .reviewFile:
            pendingQuickAction = (action, question)
            isChoosingFile = true
            isLoadingFiles = true
            changedFiles = (try? await gitService.listChangedFiles(in: repositoryURL)) ?? []
            isLoadingFiles = false
        case .compareRefs:
            pendingQuickAction = (action, question)
            if comparisonHeadDraft.isEmpty { comparisonHeadDraft = "HEAD" }
            isChoosingComparison = true
        case .analyzePullRequest:
            pendingQuickAction = (action, question)
            isChoosingPullRequest = true
        }
    }

    private enum RepositoryAIRequestMode {
        case agent
        case fixedTool(RepositoryAIToolCall)
        case file(RepositoryAIFileReference, includeDiff: Bool)
        case comparison(RepositoryAIRef, RepositoryAIRef)
        case pullRequest(Int?)
    }

    private func makeConversationTitle(from text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let title = words.prefix(5).joined(separator: " ")
        guard words.count > 5 else { return title }
        return "\(title)…"
    }
}
