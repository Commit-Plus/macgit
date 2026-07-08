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

import Foundation

enum GitProviderCredentialError: LocalizedError, Equatable {
    case noConnectedAccount(host: String)
    case multipleMatchingAccounts(host: String)
    case tokenUnavailable(username: String)
    case unsupportedRemote

    var errorDescription: String? {
        switch self {
        case .noConnectedAccount(let host):
            return "No connected provider account is available for \(host)."
        case .multipleMatchingAccounts(let host):
            return "Multiple connected provider accounts match \(host). Choose a preferred account before using private repository credentials."
        case .tokenUnavailable(let username):
            return "The local provider token for \(username) is unavailable. Reconnect the account and try again."
        case .unsupportedRemote:
            return "This remote is not supported for provider credentials."
        }
    }
}

struct GitProviderCredentialResolver {
    var accounts: [GitProviderAccount]
    var tokenVault: GitProviderTokenVault

    func credential(for remoteURLString: String, preferredAccountID: String? = nil) throws -> GitCredential? {
        guard isHTTPSRemote(remoteURLString) else { return nil }
        guard let identity = GitRemoteIdentityResolver.identity(
            from: remoteURLString,
            knownGitLabHosts: connectedGitLabHosts
        ) else {
            return nil
        }

        let matchingAccounts = accounts.filter { account in
            account.provider == identity.provider && normalizedHost(account.hostURL) == normalizedHost(identity.hostURL)
        }
        guard !matchingAccounts.isEmpty else { return nil }

        let account: GitProviderAccount
        if let preferredAccountID {
            guard let preferred = matchingAccounts.first(where: { $0.id == preferredAccountID }) else {
                throw GitProviderCredentialError.noConnectedAccount(host: normalizedHost(identity.hostURL))
            }
            account = preferred
        } else {
            guard matchingAccounts.count == 1, let onlyAccount = matchingAccounts.first else {
                throw GitProviderCredentialError.multipleMatchingAccounts(host: normalizedHost(identity.hostURL))
            }
            account = onlyAccount
        }

        guard let token = try tokenVault.readToken(for: account), !token.accessToken.isEmpty else {
            throw GitProviderCredentialError.tokenUnavailable(username: account.username)
        }
        return GitCredential(username: account.username, token: token.accessToken)
    }

    private func isHTTPSRemote(_ remoteURLString: String) -> Bool {
        guard let url = URL(string: remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "https"
    }

    private var connectedGitLabHosts: Set<String> {
        Set(accounts.compactMap { account in
            guard account.provider == .gitlab else { return nil }
            return normalizedHost(account.hostURL)
        })
    }

    private func normalizedHost(_ url: URL) -> String {
        (url.host(percentEncoded: false) ?? url.absoluteString).lowercased()
    }
}
