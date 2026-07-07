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
    private let authService: GitProviderAuthenticating?
    private let configuration: GitHubProviderAuthConfiguration?
    private let openURL: (URL) -> Bool
    private var macgitUID: String?

    init(
        store: GitProviderAccountStore,
        tokenVault: GitProviderTokenVault,
        authService: GitProviderAuthenticating? = nil,
        configuration: GitHubProviderAuthConfiguration? = nil,
        openURL: @escaping (URL) -> Bool = { _ in false }
    ) {
        self.store = store
        self.tokenVault = tokenVault
        self.authService = authService
        self.configuration = configuration
        self.openURL = openURL
    }

    func updateMacgitAccount(_ account: AccountSnapshot?) async {
        macgitUID = account?.uid
        guard account != nil else {
            accounts = []
            errorMessage = nil
            isLoading = false
            pendingDeviceAuthorization = nil
            return
        }
        await reload()
    }

    func connectGitHub() async {
        await startGitHubDeviceAuthorization()
    }

    func reconnect(_ account: GitProviderAccount) async {
        guard account.provider == .github else { return }
        await startGitHubDeviceAuthorization()
    }

    func reload() async {
        guard let macgitUID else {
            accounts = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let storedAccounts = try await store.accounts(forMacgitUID: macgitUID)
            accounts = try storedAccounts.map { account in
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
        guard macgitUID == account.macgitUID else { return }

        errorMessage = nil
        do {
            try tokenVault.deleteToken(for: account)
            try await store.delete(accountID: account.id, macgitUID: account.macgitUID)
            accounts.removeAll { $0.id == account.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openPendingDeviceVerification() {
        guard let pendingDeviceAuthorization else { return }
        _ = openURL(pendingDeviceAuthorization.verificationURI)
    }

    private func startGitHubDeviceAuthorization() async {
        guard macgitUID != nil,
              let authService,
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
            guard let macgitUID else { return }
            let account = try await authService.fetchAccount(
                token: token,
                macgitUID: macgitUID,
                host: .githubDotCom
            )
            try await saveAuthorizedAccount(account, token: token)
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

    private func saveAuthorizedAccount(_ account: GitProviderAccount, token: GitProviderToken) async throws {
        try tokenVault.saveToken(token, for: account)
        do {
            try await store.save(account)
        } catch {
            try? tokenVault.deleteToken(for: account)
            throw error
        }

        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
    }
}
