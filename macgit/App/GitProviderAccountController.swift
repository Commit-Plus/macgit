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
final class GitProviderAccountController: ObservableObject {
    @Published private(set) var accounts: [GitProviderAccount] = []
    @Published private(set) var isLoading = false
    @Published private(set) var pendingDeviceAuthorization: GitProviderDeviceAuthorization?
    @Published var errorMessage: String?

    private let store: GitProviderAccountStore
    private let tokenVault: GitProviderTokenVault
    private let sshKeyStore: GitProviderSSHKeyStore
    private let sshAuthService: GitProviderSSHAuthenticating
    private let authService: GitProviderAuthenticating?
    private let configuration: GitHubProviderAuthConfiguration?
    private let gitLabAuthService: (any GitLabProviderOAuthAuthenticating)?
    private let gitLabRedirectURI: URL
    private let openURL: (URL) -> Bool
    private var pendingOAuthSession: GitProviderOAuthSession?

    private var accountOwnerID: String { store.accountOwnerID }

    init(
        store: GitProviderAccountStore,
        tokenVault: GitProviderTokenVault,
        sshKeyStore: GitProviderSSHKeyStore = UserDefaultsGitProviderSSHKeyStore(),
        sshAuthService: GitProviderSSHAuthenticating = GitProviderSSHAuthService(),
        authService: GitProviderAuthenticating? = nil,
        configuration: GitHubProviderAuthConfiguration? = nil,
        gitLabAuthService: (any GitLabProviderOAuthAuthenticating)? = nil,
        gitLabRedirectURI: URL = GitLabProviderAuthConfiguration.appConfiguration().redirectURI,
        openURL: @escaping (URL) -> Bool = { _ in false }
    ) {
        self.store = store
        self.tokenVault = tokenVault
        self.sshKeyStore = sshKeyStore
        self.sshAuthService = sshAuthService
        self.authService = authService
        self.configuration = configuration
        self.gitLabAuthService = gitLabAuthService
        self.gitLabRedirectURI = gitLabRedirectURI
        self.openURL = openURL
    }

    func updateMacgitAccount(_ account: AccountSnapshot?) async {
        let previousAccounts = accounts
        if account == nil {
            pendingDeviceAuthorization = nil
            pendingOAuthSession = nil
        }
        do {
            try await store.updateCloudAccount(uid: account?.uid)
        } catch {
            errorMessage = error.localizedDescription
        }
        await reload()
        for previousAccount in previousAccounts where !accounts.contains(where: {
            hasSameProviderIdentity($0, previousAccount)
        }) {
            try? tokenVault.deleteToken(for: previousAccount)
            try? sshKeyStore.deleteKey(for: previousAccount)
        }
    }

    func connectGitHub() async {
        await startGitHubDeviceAuthorization()
    }

    func connectGitLabDotCom() async {
        await startGitLabDeviceAuthorization(host: .gitlabDotCom)
    }

    func connectSelfHostedGitLab(hostURL: URL) async {
        await startGitLabDeviceAuthorization(host: GitProviderHost(kind: .gitlab, baseURL: hostURL).normalized)
    }

    func reconnect(_ account: GitProviderAccount) async {
        switch account.provider {
        case .github:
            await startGitHubDeviceAuthorization()
        case .gitlab:
            await startGitLabDeviceAuthorization(host: GitProviderHost(kind: .gitlab, baseURL: account.hostURL))
        }
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let storedAccounts = try await store.accounts()
            accounts = try storedAccounts.map { account in
                if account.transportProtocol == .ssh {
                    guard try sshKeyStore.key(for: account) != nil else {
                        var unavailableAccount = account
                        unavailableAccount.tokenStatus = .unavailableOnThisDevice
                        return unavailableAccount
                    }
                    return account
                }
                guard try tokenVault.readToken(for: account) != nil else {
                    var unavailableAccount = account
                    unavailableAccount.tokenStatus = .unavailableOnThisDevice
                    return unavailableAccount
                }
                return account
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect(_ account: GitProviderAccount) async {
        errorMessage = nil
        do {
            try tokenVault.deleteToken(for: account)
            try sshKeyStore.deleteKey(for: account)
            try await store.delete(accountID: account.id)
            accounts.removeAll { $0.id == account.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openPendingDeviceVerification() {
        guard let pendingDeviceAuthorization else { return }
        _ = openURL(pendingDeviceAuthorization.verificationURI)
    }

    func handleProviderOAuthCallback(_ url: URL) async -> Bool {
        guard let session = pendingOAuthSession else { return false }

        let callback: GitProviderOAuthCallback
        do {
            callback = try GitProviderOAuthCallback.parse(url, for: session)
        } catch GitProviderOAuthError.unsupportedCallback {
            return false
        } catch {
            errorMessage = error.localizedDescription
            pendingOAuthSession = nil
            return true
        }

        guard let gitLabAuthService else {
            errorMessage = GitProviderAuthError.invalidConfiguration.localizedDescription
            pendingOAuthSession = nil
            return true
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            pendingOAuthSession = nil
        }

        do {
            let token = try await gitLabAuthService.exchangeCallback(callback, session: session)
            let account = try await gitLabAuthService.fetchAccount(
                token: token,
                macgitUID: accountOwnerID,
                host: session.host
            )
            try await saveAuthorizedAccount(account, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        return true
    }

    func credentialResolver(
        preferredAccountIDsByRemoteIdentity: [String: String] = [:]
    ) -> GitProviderCredentialResolver {
        GitProviderCredentialResolver(
            accounts: accounts,
            tokenVault: tokenVault,
            sshKeyStore: sshKeyStore,
            preferredAccountIDsByRemoteIdentity: preferredAccountIDsByRemoteIdentity
        )
    }

    func sshKey(for account: GitProviderAccount) throws -> GitProviderSSHKey? {
        try sshKeyStore.key(for: account)
    }

    func saveConnectionSettings(
        account: GitProviderAccount,
        transportProtocol: GitProviderTransportProtocol,
        sshKey: GitProviderSSHKey?
    ) async {
        errorMessage = nil
        var updatedAccount = account
        updatedAccount.transportProtocol = transportProtocol

        do {
            if transportProtocol == .ssh, let sshKey {
                try sshKeyStore.saveKey(sshKey, for: updatedAccount)
            } else {
                try sshKeyStore.deleteKey(for: updatedAccount)
            }
            try await store.save(updatedAccount)
            publish(updatedAccount)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connectSSH(host: GitProviderHost, key: GitProviderSSHKey) async {
        let macgitUID = accountOwnerID

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let normalizedHost = host.normalized
        do {
            let authentication = try await sshAuthService.authenticate(host: normalizedHost, keyPath: key.path)
            let account = GitProviderAccount(
                id: sshAccountID(
                    macgitUID: macgitUID,
                    provider: normalizedHost.kind,
                    hostURL: normalizedHost.baseURL,
                    username: authentication.username
                ),
                macgitUID: macgitUID,
                provider: normalizedHost.kind,
                hostURL: normalizedHost.baseURL,
                providerUserID: authentication.username,
                username: authentication.username,
                displayName: nil,
                avatarURL: nil,
                scopes: [],
                permissions: [:],
                tokenStatus: .valid,
                transportProtocol: .ssh,
                connectedAt: Date(),
                lastValidatedAt: Date()
            )

            try sshKeyStore.saveKey(key, for: account)
            do {
                try await store.save(account)
            } catch {
                try? sshKeyStore.deleteKey(for: account)
                throw error
            }

            publish(account)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startGitHubDeviceAuthorization() async {
        guard let authService,
              let configuration,
              !configuration.clientID.isEmpty else {
            errorMessage = GitProviderAuthError.invalidConfiguration.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        pendingDeviceAuthorization = nil
        defer {
            isLoading = false
            pendingDeviceAuthorization = nil
        }

        do {
            let authorization = try await authService.requestDeviceAuthorization()
            pendingDeviceAuthorization = authorization
            guard openURL(authorization.verificationURI) else {
                errorMessage = "Commit+ could not open the GitHub device authorization page."
                return
            }

            let token = try await waitForGitHubDeviceAuthorization(authorization, authService: authService)
            let account = try await authService.fetchAccount(
                token: token,
                macgitUID: accountOwnerID,
                host: .githubDotCom
            )
            try await saveAuthorizedAccount(account, token: token)
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func waitForGitHubDeviceAuthorization(
        _ authorization: GitProviderDeviceAuthorization,
        authService: GitProviderAuthenticating
    ) async throws -> GitProviderToken {
        let startedAt = Date()
        var interval = authorization.interval

        while Date().timeIntervalSince(startedAt) < TimeInterval(authorization.expiresIn) {
            if interval > 0 {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } else {
                await Task.yield()
            }

            do {
                return try await authService.pollDeviceAuthorization(authorization)
            } catch GitProviderAuthError.authorizationPending {
                continue
            } catch GitProviderAuthError.slowDown(let nextInterval) {
                interval = nextInterval
                continue
            }
        }

        throw GitProviderAuthError.deviceCodeExpired
    }

    private func startGitLabDeviceAuthorization(host: GitProviderHost) async {
        guard let gitLabAuthService else {
            errorMessage = gitLabInvalidConfigurationMessage
            return
        }

        isLoading = true
        errorMessage = nil
        pendingDeviceAuthorization = nil
        defer {
            isLoading = false
            pendingDeviceAuthorization = nil
        }

        let normalizedHost = host.normalized
        do {
            let authorization = try await gitLabAuthService.requestDeviceAuthorization(host: normalizedHost)
            pendingDeviceAuthorization = authorization
            guard openURL(authorization.verificationURI) else {
                errorMessage = "Commit+ could not open the GitLab device authorization page."
                return
            }

            let token = try await waitForGitLabDeviceAuthorization(
                authorization,
                host: normalizedHost,
                authService: gitLabAuthService
            )
            let account = try await gitLabAuthService.fetchAccount(
                token: token,
                macgitUID: accountOwnerID,
                host: normalizedHost
            )
            try await saveAuthorizedAccount(account, token: token)
        } catch is CancellationError {
            errorMessage = nil
        } catch GitProviderAuthError.invalidConfiguration {
            errorMessage = gitLabInvalidConfigurationMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func waitForGitLabDeviceAuthorization(
        _ authorization: GitProviderDeviceAuthorization,
        host: GitProviderHost,
        authService: any GitLabProviderOAuthAuthenticating
    ) async throws -> GitProviderToken {
        let startedAt = Date()
        var interval = authorization.interval

        while Date().timeIntervalSince(startedAt) < TimeInterval(authorization.expiresIn) {
            if interval > 0 {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            } else {
                await Task.yield()
            }

            do {
                return try await authService.pollDeviceAuthorization(authorization, host: host)
            } catch GitProviderAuthError.authorizationPending {
                continue
            } catch GitProviderAuthError.slowDown(let nextInterval) {
                interval = nextInterval
                continue
            }
        }

        throw GitProviderAuthError.deviceCodeExpired
    }

    private func startGitLabOAuth(host: GitProviderHost) async {
        guard let gitLabAuthService else {
            errorMessage = gitLabInvalidConfigurationMessage
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let session = GitProviderOAuthSession(
            provider: .gitlab,
            host: host.normalized,
            state: UUID().uuidString,
            codeVerifier: GitProviderPKCE.generateVerifier(),
            redirectURI: gitLabRedirectURI
        )

        do {
            let authorizationURL = try gitLabAuthService.authorizationURL(for: session)
            guard openURL(authorizationURL) else {
                errorMessage = "Commit+ could not open the GitLab authorization page."
                pendingOAuthSession = nil
                return
            }
            pendingOAuthSession = session
        } catch GitProviderAuthError.invalidConfiguration {
            errorMessage = gitLabInvalidConfigurationMessage
            pendingOAuthSession = nil
        } catch {
            errorMessage = error.localizedDescription
            pendingOAuthSession = nil
        }
    }

    private var gitLabInvalidConfigurationMessage: String {
        "GitLab account connection is not configured."
    }

    private func sshAccountID(
        macgitUID: String,
        provider: GitProviderKind,
        hostURL: URL,
        username: String
    ) -> String {
        let hostIdentifier = (hostURL.host(percentEncoded: false) ?? hostURL.absoluteString).lowercased()
        return "\(macgitUID):\(provider.rawValue):\(hostIdentifier):\(username)"
    }

    private func saveAuthorizedAccount(_ account: GitProviderAccount, token: GitProviderToken) async throws {
        try tokenVault.saveToken(token, for: account)
        do {
            try await store.save(account)
        } catch {
            try? tokenVault.deleteToken(for: account)
            throw error
        }

        publish(account)
    }

    private func publish(_ account: GitProviderAccount) {
        accounts.removeAll {
            $0.id == account.id || hasSameProviderIdentity($0, account)
        }
        accounts.append(account)
    }

    private func hasSameProviderIdentity(
        _ lhs: GitProviderAccount,
        _ rhs: GitProviderAccount
    ) -> Bool {
        lhs.provider == rhs.provider
            && lhs.hostURL.host(percentEncoded: false)?.lowercased()
                == rhs.hostURL.host(percentEncoded: false)?.lowercased()
            && lhs.providerUserID == rhs.providerUserID
    }
}
