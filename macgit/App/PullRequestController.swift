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
    @Published var detailErrorMessage: String?
    @Published var stateFilter: PullRequestListFilter = .open
    @Published var createdByMeOnly = false
    @Published private(set) var currentPage = 1
    @Published private(set) var hasPreviousPage = false
    @Published private(set) var hasNextPage = false
    @Published private(set) var selectedProviderAccountID: String?
    @Published private(set) var selectedDetail: PullRequestDetail?
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var createDraftSeed: PullRequestDraftSeed?
    @Published private(set) var isPerformingAction = false
    @Published private(set) var accountConnectionHost: GitProviderHost?

    private let providerAccountController: GitProviderAccountController
    private let tokenVault: GitProviderTokenVault
    private let services: [GitProviderKind: any PullRequestProviding]
    private let remoteNameProvider: (URL) async -> String?
    private let remoteURLProvider: (URL, String) async -> String?
    private let currentBranchProvider: (URL) async -> String?
    private let localBranchesProvider: (URL) async -> [String]
    private let fetchPullRequestRef: (String, String, String, URL, GitProviderCredentialResolver?) async throws -> Void
    private let checkoutBranch: (String, URL) async throws -> Void
    private let openURL: (URL) -> Bool
    private var activeRepository: GitRepositoryIdentity?
    private var activeRepositoryURL: URL?
    private var activeRemoteName: String?
    private var activeRemoteURLString: String?
    private var activeToken: GitProviderToken?
    private let pullRequestPageSize = 30

    init(
        providerAccountController: GitProviderAccountController,
        tokenVault: GitProviderTokenVault,
        services: [GitProviderKind: any PullRequestProviding],
        remoteNameProvider: @escaping (URL) async -> String? = { repositoryURL in
            let remotes = await GitStatusService.shared.remotes(in: repositoryURL)
            return remotes.first(where: { $0 == "origin" }) ?? remotes.first
        },
        remoteURLProvider: @escaping (URL, String) async -> String? = { repositoryURL, remote in
            let remoteURL = await GitStatusService.shared.remoteURL(remote: remote, in: repositoryURL)
            return remoteURL.isEmpty ? nil : remoteURL
        },
        currentBranchProvider: @escaping (URL) async -> String? = { repositoryURL in
            await GitStatusService.shared.currentBranch(in: repositoryURL)
        },
        localBranchesProvider: @escaping (URL) async -> [String] = { repositoryURL in
            await GitStatusService.shared.localBranches(in: repositoryURL)
        },
        fetchPullRequestRef: @escaping (String, String, String, URL, GitProviderCredentialResolver?) async throws -> Void = { remote, reference, localBranch, repositoryURL, credentialResolver in
            try await GitStatusService.shared.fetchPullRequestRef(
                remote: remote,
                reference: reference,
                localBranch: localBranch,
                in: repositoryURL,
                credentialResolver: credentialResolver
            )
        },
        checkoutBranch: @escaping (String, URL) async throws -> Void = { branch, repositoryURL in
            try await GitStatusService.shared.checkoutBranch(
                branch,
                inWorktree: repositoryURL,
                force: false,
                repositoryURL: repositoryURL
            )
        },
        openURL: @escaping (URL) -> Bool = { _ in false }
    ) {
        self.providerAccountController = providerAccountController
        self.tokenVault = tokenVault
        self.services = services
        self.remoteNameProvider = remoteNameProvider
        self.remoteURLProvider = remoteURLProvider
        self.currentBranchProvider = currentBranchProvider
        self.localBranchesProvider = localBranchesProvider
        self.fetchPullRequestRef = fetchPullRequestRef
        self.checkoutBranch = checkoutBranch
        self.openURL = openURL
    }

    var visibleItems: [PullRequestSummary] {
        items.filter { item in
            stateFilter.includes(item.state)
                && (!createdByMeOnly || item.author.username == selectedProviderAccountUsername)
        }
    }

    var selectedProviderAccountUsername: String? {
        guard let selectedProviderAccountID else { return nil }
        return providerAccountController.accounts.first { $0.id == selectedProviderAccountID }?.username
    }

    var accountConnectionProvider: GitProviderKind? {
        accountConnectionHost?.kind
    }

    var needsAccountConnectionAction: Bool {
        errorMessage == "Connect Account..." || errorMessage == "Reconnect..."
    }

    var accountConnectionActionTitle: String {
        errorMessage == "Reconnect..." ? "Reconnect" : "Connect Account"
    }

    func loadPullRequests(repositoryURL: URL, page: Int = 1) async {
        activeRepositoryURL = repositoryURL
        guard let remoteName = await remoteNameProvider(repositoryURL),
              let remoteURLString = await remoteURLProvider(repositoryURL, remoteName) else {
            items = []
            resetPagination()
            activeRemoteName = nil
            activeRemoteURLString = nil
            accountConnectionHost = nil
            errorMessage = "No remotes configured."
            return
        }
        activeRemoteName = remoteName
        await loadPullRequests(remoteURLString: remoteURLString, page: page)
    }

    func loadPullRequests(repositoryURL: URL, remoteName: String, page: Int = 1) async {
        activeRepositoryURL = repositoryURL
        guard let remoteURLString = await remoteURLProvider(repositoryURL, remoteName) else {
            items = []
            resetPagination()
            activeRemoteName = nil
            activeRemoteURLString = nil
            accountConnectionHost = nil
            errorMessage = "No remotes configured."
            return
        }
        activeRemoteName = remoteName
        await loadPullRequests(remoteURLString: remoteURLString, page: page)
    }

    func loadPullRequests(remoteURLString: String, page: Int = 1) async {
        isLoading = true
        errorMessage = nil
        accountConnectionHost = nil
        defer { isLoading = false }

        guard let remoteIdentity = GitRemoteIdentityResolver.identity(
            from: remoteURLString,
            knownGitLabHosts: connectedGitLabHosts
        ) else {
            items = []
            resetPagination()
            selectedProviderAccountID = nil
            activeRepository = nil
            activeToken = nil
            accountConnectionHost = nil
            errorMessage = PullRequestProviderError.unsupportedProvider.localizedDescription
            return
        }

        let repository = GitRepositoryIdentity(
            provider: remoteIdentity.provider,
            hostURL: remoteIdentity.hostURL,
            owner: remoteIdentity.ownerPath,
            name: remoteIdentity.repositoryName
        )
        activeRemoteURLString = remoteURLString

        let matchingAccounts = matchingAccounts(for: repository)
        guard !matchingAccounts.isEmpty else {
            items = []
            resetPagination()
            selectedProviderAccountID = nil
            activeRepository = nil
            activeToken = nil
            accountConnectionHost = GitProviderHost(kind: repository.provider, baseURL: repository.hostURL).normalized
            errorMessage = "Connect Account..."
            return
        }

        guard let apiCredential = apiCredential(for: matchingAccounts) else {
            items = []
            resetPagination()
            selectedProviderAccountID = nil
            activeRepository = nil
            activeToken = nil
            accountConnectionHost = GitProviderHost(kind: repository.provider, baseURL: repository.hostURL).normalized
            errorMessage = matchingAccounts.contains(where: supportsProviderAPI) ? "Reconnect..." : "Connect Account..."
            return
        }
        selectedProviderAccountID = apiCredential.account.id
        let token = apiCredential.token

        guard let service = services[repository.provider] else {
            items = []
            resetPagination()
            activeRepository = nil
            activeToken = nil
            accountConnectionHost = nil
            errorMessage = PullRequestProviderError.unsupportedProvider.localizedDescription
            return
        }

        do {
            let pageResult = try await service.listPullRequests(
                repository: repository,
                token: token,
                filter: stateFilter,
                page: page,
                perPage: pullRequestPageSize
            )
            items = pageResult.items
            currentPage = pageResult.page
            hasPreviousPage = pageResult.hasPreviousPage
            hasNextPage = pageResult.hasNextPage
            activeRepository = repository
            activeToken = token
            accountConnectionHost = nil
            errorMessage = nil
        } catch let error as PullRequestProviderError {
            items = []
            resetPagination()
            accountConnectionHost = nil
            errorMessage = error.localizedDescription
        } catch {
            items = []
            resetPagination()
            accountConnectionHost = nil
            errorMessage = error.localizedDescription
        }
    }

    func loadPreviousPage(repositoryURL: URL) async {
        guard hasPreviousPage, currentPage > 1 else { return }
        await loadPullRequests(repositoryURL: repositoryURL, page: currentPage - 1)
    }

    func loadNextPage(repositoryURL: URL) async {
        guard hasNextPage else { return }
        await loadPullRequests(repositoryURL: repositoryURL, page: currentPage + 1)
    }

    func openInBrowser(_ summary: PullRequestSummary) {
        _ = openURL(summary.webURL)
    }

    func loadPullRequestDetail(_ summary: PullRequestSummary) async {
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            detailErrorMessage = "Pull request details are unavailable."
            return
        }

        isLoadingDetail = true
        detailErrorMessage = nil
        defer { isLoadingDetail = false }

        do {
            selectedDetail = try await service.pullRequestDetail(
                repository: repository,
                token: token,
                number: summary.number
            )
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    func clearSelectedDetail() {
        selectedDetail = nil
    }

    func openChangesInBrowser(_ detail: PullRequestDetail) {
        _ = openURL(detail.changesURL)
    }

    func presentCreatePullRequest(sourceBranch requestedSourceBranch: String? = nil) async {
        guard let repository = activeRepository,
              let repositoryURL = activeRepositoryURL else {
            detailErrorMessage = "Pull request creation is unavailable."
            return
        }

        let localBranches = await localBranchesProvider(repositoryURL).filter { !$0.isEmpty }
        let currentBranch = await currentBranchProvider(repositoryURL)
        let normalizedRequestedSource = requestedSourceBranch?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceBranch = (normalizedRequestedSource?.isEmpty == false ? normalizedRequestedSource : nil)
            ?? currentBranch
            ?? localBranches.first
        guard let sourceBranch else {
            detailErrorMessage = "No local branches are available for a pull request."
            return
        }

        let knownTargetBranches = Set(items.map(\.target.ref).filter { !$0.isEmpty })
        let defaultTargetBranch = knownTargetBranches.first(where: { $0 != sourceBranch })
            ?? localBranches.first(where: { $0 != sourceBranch && $0 == "main" })
            ?? localBranches.first(where: { $0 != sourceBranch })
            ?? "main"
        let targetBranches = Array(knownTargetBranches.union(localBranches).union([defaultTargetBranch])).sorted()

        createDraftSeed = PullRequestDraftSeed(
            repository: repository,
            sourceBranches: Array(Set(localBranches).union([sourceBranch])).sorted(),
            targetBranches: targetBranches,
            sourceBranch: sourceBranch,
            targetBranch: defaultTargetBranch,
            suggestedTitle: suggestedTitle(for: sourceBranch)
        )
    }

    func dismissCreatePullRequest() {
        createDraftSeed = nil
    }

    func createPullRequest(_ draft: PullRequestDraft) async {
        do {
            try draft.validate()
        } catch {
            detailErrorMessage = error.localizedDescription
            return
        }
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            detailErrorMessage = "Pull request creation is unavailable."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            _ = try await service.createPullRequest(draft, token: token)
            createDraftSeed = nil
            if let activeRemoteURLString {
                await loadPullRequests(remoteURLString: activeRemoteURLString, page: 1)
            }
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    func comment(on pullRequest: PullRequestSummary, body: String) async {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            detailErrorMessage = "Pull request comment is required."
            return
        }
        guard let repository = activeRepository,
              let token = activeToken,
              let service = services[repository.provider] else {
            detailErrorMessage = "Pull request comments are unavailable."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            try await service.createComment(
                body: trimmedBody,
                on: pullRequest,
                repository: repository,
                token: token
            )
            if selectedDetail?.summary.number == pullRequest.number {
                await loadPullRequestDetail(pullRequest)
            }
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    func checkout(_ pullRequest: PullRequestSummary) async {
        guard let repositoryURL = activeRepositoryURL else {
            detailErrorMessage = "Pull request checkout is unavailable."
            return
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        do {
            let localBranches = await localBranchesProvider(repositoryURL)
            if localBranches.contains(pullRequest.source.ref) {
                try await checkoutBranch(pullRequest.source.ref, repositoryURL)
                return
            }

            let branchName = "pr/\(pullRequest.number)"
            if activeRepository?.provider == .github {
                guard let activeRemoteName else {
                    throw PullRequestProviderError.providerMessage("No remotes configured.")
                }
                try await fetchPullRequestRef(
                    activeRemoteName,
                    "pull/\(pullRequest.number)/head",
                    branchName,
                    repositoryURL,
                    providerAccountController.credentialResolver()
                )
                try await checkoutBranch(branchName, repositoryURL)
                return
            }

            try await checkoutBranch(pullRequest.source.ref, repositoryURL)
        } catch {
            detailErrorMessage = error.localizedDescription
        }
    }

    private func matchingAccounts(for repository: GitRepositoryIdentity) -> [GitProviderAccount] {
        let repositoryHost = normalizedHost(repository.hostURL)
        return providerAccountController.accounts.filter { account in
            account.provider == repository.provider && normalizedHost(account.hostURL) == repositoryHost
        }
    }

    private func apiCredential(for accounts: [GitProviderAccount]) -> (
        account: GitProviderAccount,
        token: GitProviderToken
    )? {
        let prioritizedAccounts = prioritizedAccounts(accounts)
        for account in prioritizedAccounts {
            guard supportsProviderAPI(account) else { continue }
            do {
                guard let token = try tokenVault.readToken(for: account), !token.accessToken.isEmpty else {
                    continue
                }
                return (account, token)
            } catch {
                continue
            }
        }
        return nil
    }

    private func prioritizedAccounts(_ accounts: [GitProviderAccount]) -> [GitProviderAccount] {
        guard let selectedProviderAccountID,
              let selected = accounts.first(where: { $0.id == selectedProviderAccountID }) else {
            return accounts
        }
        return [selected] + accounts.filter { $0.id != selected.id }
    }

    private func supportsProviderAPI(_ account: GitProviderAccount) -> Bool {
        account.transportProtocol == .https || !account.scopes.isEmpty
    }

    private func resetPagination() {
        currentPage = 1
        hasPreviousPage = false
        hasNextPage = false
    }

    private var connectedGitLabHosts: Set<String> {
        Set(providerAccountController.accounts.compactMap { account in
            guard account.provider == .gitlab else { return nil }
            return normalizedHost(account.hostURL)
        })
    }

    private func normalizedHost(_ url: URL) -> String {
        (url.host(percentEncoded: false) ?? url.absoluteString).lowercased()
    }

    private func suggestedTitle(for branch: String) -> String {
        let branchSuffix = branch.split(separator: "/").last.map(String.init) ?? branch
        let words = branchSuffix
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { segment -> String in
                let lower = segment.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
        return words.joined(separator: " ")
    }
}
