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
final class AIProviderController: ObservableObject {
    @Published private(set) var availabilityByProviderID: [AIProviderID: AIProviderAvailability] = [:]
    @Published private(set) var configuredProviderIDs: Set<AIProviderID> = []
    @Published private(set) var customModelsByProviderID: [AIProviderID: String] = [:]
    @Published private(set) var isGenerating = false
    @Published private(set) var selectedProviderID: AIProviderID

    private let registry: AIProviderRegistry
    private let snapshotLoader: any CommitChangeSnapshotLoading
    private let repositoryToolExecutor: any RepositoryAIToolExecuting
    private let repositoryFileContextService: any RepositoryAIFileContextServicing
    private let repositoryAgentHarness: RepositoryAIAgentHarness
    private let defaults: UserDefaults
    private let credentialStore: any AIProviderCredentialStore
    private let modelStore: any AIProviderModelStore
    private let selectedProviderDefaultsKey = "ai.commitMessage.selectedProvider"

    convenience init() {
        let credentialStore = KeychainAIProviderCredentialStore()
        let modelStore = UserDefaultsAIProviderModelStore()
        self.init(
            registry: .live(credentialStore: credentialStore, modelStore: modelStore),
            snapshotLoader: GitStatusService.shared,
            repositoryToolExecutor: GitStatusService.shared,
            repositoryFileContextService: GitStatusService.shared,
            repositoryAgentHarness: RepositoryAIAgentHarness(),
            defaults: .standard,
            credentialStore: credentialStore,
            modelStore: modelStore
        )
    }

    init(
        registry: AIProviderRegistry,
        snapshotLoader: any CommitChangeSnapshotLoading,
        repositoryToolExecutor: any RepositoryAIToolExecuting = GitStatusService.shared,
        repositoryFileContextService: any RepositoryAIFileContextServicing = GitStatusService.shared,
        repositoryAgentHarness: RepositoryAIAgentHarness = RepositoryAIAgentHarness(),
        defaults: UserDefaults,
        credentialStore: any AIProviderCredentialStore = KeychainAIProviderCredentialStore(),
        modelStore: any AIProviderModelStore = UserDefaultsAIProviderModelStore()
    ) {
        self.registry = registry
        self.snapshotLoader = snapshotLoader
        self.repositoryToolExecutor = repositoryToolExecutor
        self.repositoryFileContextService = repositoryFileContextService
        self.repositoryAgentHarness = repositoryAgentHarness
        self.defaults = defaults
        self.credentialStore = credentialStore
        self.modelStore = modelStore
        let storedID = defaults.string(forKey: selectedProviderDefaultsKey).map(AIProviderID.init(rawValue:))
        if let storedID, registry.provider(for: storedID)?.descriptor.isImplemented == true {
            selectedProviderID = storedID
        } else {
            selectedProviderID = .appleIntelligence
        }

        for descriptor in registry.descriptors {
            availabilityByProviderID[descriptor.id] = descriptor.isImplemented ? .checking : .comingSoon
            if descriptor.dataProcessing == .cloud,
               (try? credentialStore.apiKey(for: descriptor.id)) != nil {
                configuredProviderIDs.insert(descriptor.id)
            }
            if let customModel = modelStore.customModel(for: descriptor.id) {
                customModelsByProviderID[descriptor.id] = customModel
            }
        }
    }

    var descriptors: [AIProviderDescriptor] {
        registry.descriptors
    }

    var selectedDescriptor: AIProviderDescriptor {
        registry.provider(for: selectedProviderID)?.descriptor
            ?? registry.descriptors[0]
    }

    var selectedProviderAvailability: AIProviderAvailability {
        availabilityByProviderID[selectedProviderID] ?? .checking
    }

    func availability(for id: AIProviderID) -> AIProviderAvailability {
        availabilityByProviderID[id] ?? .checking
    }

    func selectProvider(_ id: AIProviderID) {
        guard registry.provider(for: id)?.descriptor.isImplemented == true else { return }
        selectedProviderID = id
        defaults.set(id.rawValue, forKey: selectedProviderDefaultsKey)
    }

    func isAPIKeyConfigured(for id: AIProviderID) -> Bool {
        configuredProviderIDs.contains(id)
    }

    func canSelect(
        _ descriptor: AIProviderDescriptor,
        restrictedProviderAccess: FeatureAccessDecision
    ) -> Bool {
        guard descriptor.isImplemented,
              availability(for: descriptor.id).isAvailable else {
            return false
        }
        if descriptor.dataProcessing == .cloud,
           !isAPIKeyConfigured(for: descriptor.id) {
            return false
        }
        if descriptor.requiresProToConfigureAPIKey,
           !restrictedProviderAccess.isAllowed {
            return false
        }
        return true
    }

    func model(for descriptor: AIProviderDescriptor) -> String? {
        customModelsByProviderID[descriptor.id] ?? descriptor.defaultModel
    }

    func configurationDrafts() -> [AIProviderConfigurationDraft] {
        descriptors.compactMap { descriptor in
            guard descriptor.dataProcessing == .cloud,
                  let model = model(for: descriptor) else { return nil }
            return AIProviderConfigurationDraft(id: descriptor.id, model: model)
        }
    }

    func saveAPIKey(_ apiKey: String, for id: AIProviderID) throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw CommitMessageGenerationError.providerRequestFailed("Enter an API key before saving.")
        }
        try credentialStore.saveAPIKey(normalizedKey, for: id)
        configuredProviderIDs.insert(id)
    }

    func removeAPIKey(for id: AIProviderID) throws {
        try credentialStore.deleteAPIKey(for: id)
        configuredProviderIDs.remove(id)
        if selectedProviderID == id {
            selectProvider(.appleIntelligence)
        }
    }

    func applyProviderChanges(
        _ drafts: [AIProviderConfigurationDraft],
        restrictedProviderAccess: FeatureAccessDecision
    ) throws {
        for draft in drafts where !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let descriptor = registry.provider(for: draft.id)?.descriptor else { continue }
            if descriptor.requiresProToConfigureAPIKey,
               !restrictedProviderAccess.isAllowed {
                throw AIProviderConfigurationError.requiresPro(providerName: descriptor.displayName)
            }
        }

        for draft in drafts {
            if !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try saveAPIKey(draft.apiKey, for: draft.id)
            } else if draft.shouldRemoveAPIKey {
                try removeAPIKey(for: draft.id)
            }

            guard let descriptor = registry.provider(for: draft.id)?.descriptor,
                  let defaultModel = descriptor.defaultModel else { continue }
            let normalizedModel = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedModel.isEmpty || normalizedModel == defaultModel {
                modelStore.resetModel(for: draft.id)
                customModelsByProviderID.removeValue(forKey: draft.id)
            } else {
                modelStore.saveCustomModel(normalizedModel, for: draft.id)
                customModelsByProviderID[draft.id] = normalizedModel
            }
        }
    }

    func refreshAvailability() async {
        for provider in registry.providers {
            availabilityByProviderID[provider.descriptor.id] = await provider.availability()
        }
    }

    func generateCommitMessage(
        repositoryURL: URL,
        branchName: String?,
        changeSource: CommitChangeSource,
        recentCommitSubjects: [String]
    ) async throws -> GeneratedCommitMessage {
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("A commit message is already being generated.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        let providerID = selectedProviderID
        let providerAvailability = await provider.availability()
        availabilityByProviderID[providerID] = providerAvailability
        guard providerAvailability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(providerAvailability.detail)
        }

        isGenerating = true
        defer { isGenerating = false }

        let snapshot = try await snapshotLoader.commitChangeSnapshot(
            in: repositoryURL,
            source: changeSource,
            characterBudget: provider.descriptor.inputCharacterBudget
        )
        let request = CommitMessageGenerationRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            changeSource: changeSource,
            changes: snapshot,
            recentCommitSubjects: Array(recentCommitSubjects.prefix(8))
        )
        let generated = try await provider.generateCommitMessage(request: request)
        let currentFingerprint = try await snapshotLoader.changesFingerprint(
            in: repositoryURL,
            source: changeSource
        )
        guard providerID == selectedProviderID, currentFingerprint == snapshot.fingerprint else {
            throw CommitMessageGenerationError.changesChanged(changeSource)
        }
        return generated
    }

    func answerRepositoryQuestion(
        repositoryURL: URL,
        branchName: String?,
        question: String,
        tool: RepositoryAIToolCall,
        sessionID: String? = nil
    ) async throws -> RepositoryAIAnswer {
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else {
            throw RepositoryAIError.emptyQuestion
        }
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        let providerID = selectedProviderID
        let providerAvailability = await provider.availability()
        availabilityByProviderID[providerID] = providerAvailability
        guard providerAvailability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(providerAvailability.detail)
        }

        isGenerating = true
        defer { isGenerating = false }

        let result = try await repositoryToolExecutor.execute(
            tool,
            in: repositoryURL,
            characterBudget: provider.descriptor.inputCharacterBudget
        )
        let request = RepositoryAIRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            question: normalizedQuestion,
            toolResult: result,
            sessionID: sessionID
        )
        let response = try await provider.generateRepositoryResponse(request: request)
        let currentFingerprint = try await repositoryToolExecutor.fingerprint(
            for: tool,
            in: repositoryURL
        )
        guard providerID == selectedProviderID,
              currentFingerprint == result.fingerprint else {
            throw RepositoryAIError.contextChanged
        }

        guard !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryAIError.emptyResponse
        }
        return response
    }

    func answerRepositoryFileQuestion(
        repositoryURL: URL,
        branchName: String?,
        question: String,
        reference: RepositoryAIFileReference,
        includeDiff: Bool,
        sessionID: String? = nil
    ) async throws -> (answer: RepositoryAIAnswer, manifest: RepositoryAIEvidenceManifest) {
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else { throw RepositoryAIError.emptyQuestion }
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        let providerID = selectedProviderID
        let availability = await provider.availability()
        availabilityByProviderID[providerID] = availability
        guard availability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(availability.detail)
        }

        isGenerating = true
        defer { isGenerating = false }
        let budget = provider.descriptor.inputCharacterBudget
        let result: RepositoryAIToolResult
        let manifest: RepositoryAIEvidenceManifest
        if includeDiff {
            let diff = try await repositoryFileContextService.readFileDiff(
                reference,
                contextLines: 3,
                maximumHunks: 12,
                characterBudget: budget,
                in: repositoryURL
            )
            manifest = diff.manifest
            result = RepositoryAIToolResult(
                toolName: "read_file_diff",
                title: diff.reference.displayLabel,
                fingerprint: diff.evidence.fingerprint,
                content: RepositoryAIPrompt.fileEvidence(diff),
                isTruncated: diff.isTruncated
            )
        } else {
            let context = try await repositoryFileContextService.readFileContext(
                reference,
                lineRange: nil,
                characterBudget: budget,
                in: repositoryURL
            )
            manifest = context.manifest
            result = RepositoryAIToolResult(
                toolName: "read_file_context",
                title: context.reference.displayLabel,
                fingerprint: context.evidence.fingerprint,
                content: RepositoryAIPrompt.fileEvidence(context),
                isTruncated: context.isTruncated
            )
        }
        let response = try await provider.generateRepositoryResponse(request: RepositoryAIRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            question: normalizedQuestion,
            toolResult: result,
            sessionID: sessionID
        ))
        guard providerID == selectedProviderID else { throw RepositoryAIError.contextChanged }
        guard let evidence = manifest.evidence.first else { throw RepositoryAIError.invalidResponse("Repository AI did not receive file evidence.") }
        let currentFingerprint = try await repositoryFileContextService.currentFingerprint(for: evidence.reference, in: repositoryURL)
        guard currentFingerprint == evidence.fingerprint else { throw RepositoryAIError.contextChanged }
        let validated = manifest.validatedCitations(from: response.citations)
        return (RepositoryAIAnswer(text: response.text, citations: validated.accepted), manifest)
    }

    func answerRepositoryQuestionWithAgent(
        repositoryURL: URL,
        branchName: String?,
        question: String,
        conversation: [RepositoryAIMessage] = []
    ) async throws -> RepositoryAIAgentRunResult {
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else {
            throw RepositoryAIError.emptyQuestion
        }
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }
        guard provider.supportsRepositoryAgent else {
            throw RepositoryAIAgentError.unsupportedProvider(provider.descriptor.displayName)
        }

        let providerID = selectedProviderID
        let providerAvailability = await provider.availability()
        availabilityByProviderID[providerID] = providerAvailability
        guard providerAvailability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(providerAvailability.detail)
        }

        isGenerating = true
        defer { isGenerating = false }

        let result = try await repositoryAgentHarness.answer(
            question: normalizedQuestion,
            repositoryURL: repositoryURL,
            branchName: branchName,
            conversation: conversation,
            provider: provider
        )
        guard providerID == selectedProviderID else {
            throw RepositoryAIError.contextChanged
        }
        return result
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        guard !isGenerating else {
            throw CommitMessageGenerationError.providerUnavailable("Another AI request is already running.")
        }
        guard let provider = registry.provider(for: selectedProviderID) else {
            throw CommitMessageGenerationError.providerNotImplemented
        }

        let providerID = selectedProviderID
        let providerAvailability = await provider.availability()
        availabilityByProviderID[providerID] = providerAvailability
        guard providerAvailability.isAvailable else {
            throw CommitMessageGenerationError.providerUnavailable(providerAvailability.detail)
        }

        isGenerating = true
        defer { isGenerating = false }

        let response = try await provider.generateConflictResolution(request: request)
        guard providerID == selectedProviderID else {
            throw ConflictAIResolutionError.staleFile(
                "The selected AI provider changed while conflicts were being resolved."
            )
        }
        return response
    }
}
