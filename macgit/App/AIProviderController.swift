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
    @Published private(set) var isGenerating = false
    @Published private(set) var selectedProviderID: AIProviderID

    private let registry: AIProviderRegistry
    private let snapshotLoader: any CommitChangeSnapshotLoading
    private let defaults: UserDefaults
    private let selectedProviderDefaultsKey = "ai.commitMessage.selectedProvider"

    convenience init() {
        self.init(
            registry: .live(),
            snapshotLoader: GitStatusService.shared,
            defaults: .standard
        )
    }

    init(
        registry: AIProviderRegistry,
        snapshotLoader: any CommitChangeSnapshotLoading,
        defaults: UserDefaults
    ) {
        self.registry = registry
        self.snapshotLoader = snapshotLoader
        self.defaults = defaults
        let storedID = defaults.string(forKey: selectedProviderDefaultsKey).map(AIProviderID.init(rawValue:))
        if let storedID, registry.provider(for: storedID)?.descriptor.isImplemented == true {
            selectedProviderID = storedID
        } else {
            selectedProviderID = .appleIntelligence
        }

        for descriptor in registry.descriptors {
            availabilityByProviderID[descriptor.id] = descriptor.isImplemented ? .checking : .comingSoon
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

    func refreshAvailability() async {
        for provider in registry.providers {
            availabilityByProviderID[provider.descriptor.id] = await provider.availability()
        }
    }

    func generateCommitMessage(
        repositoryURL: URL,
        branchName: String?,
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

        let snapshot = try await snapshotLoader.stagedCommitChangeSnapshot(
            in: repositoryURL,
            characterBudget: provider.descriptor.inputCharacterBudget
        )
        let request = CommitMessageGenerationRequest(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            stagedChanges: snapshot,
            recentCommitSubjects: Array(recentCommitSubjects.prefix(8))
        )
        let generated = try await provider.generateCommitMessage(request: request)
        let currentFingerprint = try await snapshotLoader.stagedChangesFingerprint(in: repositoryURL)
        guard providerID == selectedProviderID, currentFingerprint == snapshot.fingerprint else {
            throw CommitMessageGenerationError.stagedChangesChanged
        }
        return generated
    }
}
