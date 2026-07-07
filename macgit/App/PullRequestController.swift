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
final class PullRequestController: ObservableObject {
    @Published private(set) var items: [PullRequestSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var selectedProviderAccountID: String?

    private let providerAccountController: GitProviderAccountController
    private let tokenVault: GitProviderTokenVault
    private let services: [GitProviderKind: any PullRequestProviding]
    private let remoteURLProvider: (URL) async -> String?
    private let openURL: (URL) -> Bool

    init(
        providerAccountController: GitProviderAccountController,
        tokenVault: GitProviderTokenVault,
        services: [GitProviderKind: any PullRequestProviding],
        remoteURLProvider: @escaping (URL) async -> String? = { repositoryURL in
            let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
            guard let remote = remotes.first(where: { $0 == "origin" }) ?? remotes.first else {
                return nil
            }
            return await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
        },
        openURL: @escaping (URL) -> Bool = { _ in false }
    ) {
        self.providerAccountController = providerAccountController
        self.tokenVault = tokenVault
        self.services = services
        self.remoteURLProvider = remoteURLProvider
        self.openURL = openURL
    }

    func loadPullRequests(repositoryURL: URL) async {
        guard let remoteURLString = await remoteURLProvider(repositoryURL) else {
            items = []
            errorMessage = "No remotes configured."
            return
        }
        await loadPullRequests(remoteURLString: remoteURLString)
    }

    func loadPullRequests(remoteURLString: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let remoteIdentity = GitRemoteIdentityResolver.identity(from: remoteURLString) else {
            items = []
            selectedProviderAccountID = nil
            errorMessage = PullRequestProviderError.unsupportedProvider.localizedDescription
            return
        }

        let repository = GitRepositoryIdentity(
            provider: remoteIdentity.provider,
            hostURL: remoteIdentity.hostURL,
            owner: remoteIdentity.ownerPath,
            name: remoteIdentity.repositoryName
        )

        guard let account = matchingAccount(for: repository) else {
            items = []
            selectedProviderAccountID = nil
            errorMessage = "Connect Account..."
            return
        }
        selectedProviderAccountID = account.id

        let token: GitProviderToken
        do {
            guard let storedToken = try tokenVault.readToken(for: account) else {
                items = []
                errorMessage = "Reconnect..."
                return
            }
            token = storedToken
        } catch {
            items = []
            errorMessage = "Reconnect..."
            return
        }

        guard let service = services[repository.provider] else {
            items = []
            errorMessage = PullRequestProviderError.unsupportedProvider.localizedDescription
            return
        }

        do {
            items = try await service.listPullRequests(repository: repository, token: token)
            errorMessage = nil
        } catch let error as PullRequestProviderError {
            items = []
            errorMessage = error.localizedDescription
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }

    func openInBrowser(_ summary: PullRequestSummary) {
        _ = openURL(summary.webURL)
    }

    private func matchingAccount(for repository: GitRepositoryIdentity) -> GitProviderAccount? {
        let repositoryHost = normalizedHost(repository.hostURL)
        let accounts = providerAccountController.accounts.filter { account in
            account.provider == repository.provider && normalizedHost(account.hostURL) == repositoryHost
        }
        return accounts.first(where: { $0.id == selectedProviderAccountID }) ?? accounts.first
    }

    private func normalizedHost(_ url: URL) -> String {
        (url.host(percentEncoded: false) ?? url.absoluteString).lowercased()
    }
}
