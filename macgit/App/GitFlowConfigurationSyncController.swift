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

struct GitFlowConfigurationSyncOutcome {
    var configuration: GitFlowConfiguration?
    var warningMessage: String?

    static let unchanged = GitFlowConfigurationSyncOutcome(
        configuration: nil,
        warningMessage: nil
    )
}

@MainActor
final class GitFlowConfigurationSyncController: ObservableObject {
    private let cloudStore: GitFlowConfigurationCloudStore?
    private let localStore: GitFlowConfigurationStore
    private let identityResolver: any RepositoryRemoteIdentityResolving
    private let userDefaults: UserDefaults
    private let pendingUploadsKey: String

    init(
        cloudStore: GitFlowConfigurationCloudStore?,
        localStore: GitFlowConfigurationStore = GitFlowConfigurationStore(),
        identityResolver: any RepositoryRemoteIdentityResolving = RepositoryRemoteIdentityResolver(),
        userDefaults: UserDefaults = .standard,
        pendingUploadsKey: String = "dev.thanhtran.macgit.gitFlowConfiguration.pendingUploads"
    ) {
        self.cloudStore = cloudStore
        self.localStore = localStore
        self.identityResolver = identityResolver
        self.userDefaults = userDefaults
        self.pendingUploadsKey = pendingUploadsKey
    }

    func reconcile(
        repositoryURL: URL,
        fallbackConfiguration: GitFlowConfiguration,
        uid: String?
    ) async -> GitFlowConfigurationSyncOutcome {
        guard let uid, let cloudStore else { return .unchanged }

        let localResult = await localStore.loadResult(in: repositoryURL)
        if case .invalid = localResult {
            return .unchanged
        }
        guard let identity = await identityResolver.identity(in: repositoryURL) else {
            return .unchanged
        }
        let uploadID = pendingUploadID(uid: uid, repositoryID: identity.documentID)

        do {
            if isPendingUpload(uploadID) {
                if case .value(let localConfiguration) = localResult {
                    try await upload(
                        localConfiguration,
                        identity: identity,
                        uid: uid,
                        cloudStore: cloudStore
                    )
                    clearPendingUpload(uploadID)
                    return .unchanged
                }
                clearPendingUpload(uploadID)
            }

            if let cloudConfiguration = try await cloudStore.configuration(
                repositoryID: identity.documentID,
                uid: uid
            ) {
                let latestLocalResult = await localStore.loadResult(in: repositoryURL)
                if isPendingUpload(uploadID) || localConfigurationChanged(
                    from: localResult,
                    to: latestLocalResult
                ) {
                    if case .value(let latestLocalConfiguration) = latestLocalResult {
                        try await upload(
                            latestLocalConfiguration,
                            identity: identity,
                            uid: uid,
                            cloudStore: cloudStore
                        )
                        clearPendingUpload(uploadID)
                    }
                    return .unchanged
                }
                guard cloudConfiguration.canonicalKey == identity.canonicalKey else {
                    throw GitFlowCloudConfigurationDocumentError.invalidDocument
                }
                let localConfiguration: GitFlowConfiguration
                switch localResult {
                case .none:
                    localConfiguration = fallbackConfiguration
                case .value(let configuration):
                    localConfiguration = configuration
                case .invalid:
                    return .unchanged
                }
                let merged = cloudConfiguration.applying(to: localConfiguration)
                try GitFlowPlanner().validate(merged)
                try await localStore.save(merged, in: repositoryURL)
                return GitFlowConfigurationSyncOutcome(
                    configuration: merged,
                    warningMessage: nil
                )
            }

            if case .value(let localConfiguration) = localResult {
                try await upload(
                    localConfiguration,
                    identity: identity,
                    uid: uid,
                    cloudStore: cloudStore
                )
            }
            return .unchanged
        } catch {
            return GitFlowConfigurationSyncOutcome(
                configuration: nil,
                warningMessage: "Git Flow is available locally, but its configuration could not sync: \(error.localizedDescription)"
            )
        }
    }

    func save(
        _ configuration: GitFlowConfiguration,
        repositoryURL: URL,
        uid: String?
    ) async throws -> String? {
        try await localStore.save(configuration, in: repositoryURL)
        guard let uid,
              let cloudStore,
              let identity = await identityResolver.identity(in: repositoryURL) else {
            return nil
        }
        let uploadID = pendingUploadID(uid: uid, repositoryID: identity.documentID)
        markPendingUpload(uploadID)

        do {
            try await upload(
                configuration,
                identity: identity,
                uid: uid,
                cloudStore: cloudStore
            )
            clearPendingUpload(uploadID)
            return nil
        } catch {
            return "Git Flow was saved locally, but its configuration could not sync: \(error.localizedDescription)"
        }
    }

    private func upload(
        _ configuration: GitFlowConfiguration,
        identity: RepositoryBookmarkIdentity,
        uid: String,
        cloudStore: GitFlowConfigurationCloudStore
    ) async throws {
        try await cloudStore.save(
            GitFlowCloudConfiguration(
                configuration: configuration,
                canonicalKey: identity.canonicalKey
            ),
            repositoryID: identity.documentID,
            uid: uid
        )
    }

    private func localConfigurationChanged(
        from initial: GitFlowLocalStateLoadResult<GitFlowConfiguration>,
        to latest: GitFlowLocalStateLoadResult<GitFlowConfiguration>
    ) -> Bool {
        switch (initial, latest) {
        case (.none, .none):
            false
        case (.value(let initialConfiguration), .value(let latestConfiguration)):
            initialConfiguration != latestConfiguration
        default:
            true
        }
    }

    private func pendingUploadID(uid: String, repositoryID: String) -> String {
        "\(uid)|\(repositoryID)"
    }

    private func isPendingUpload(_ id: String) -> Bool {
        pendingUploadIDs.contains(id)
    }

    private func markPendingUpload(_ id: String) {
        var ids = pendingUploadIDs
        ids.insert(id)
        userDefaults.set(Array(ids), forKey: pendingUploadsKey)
    }

    private func clearPendingUpload(_ id: String) {
        var ids = pendingUploadIDs
        ids.remove(id)
        userDefaults.set(Array(ids), forKey: pendingUploadsKey)
    }

    private var pendingUploadIDs: Set<String> {
        Set(userDefaults.stringArray(forKey: pendingUploadsKey) ?? [])
    }
}
