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

enum GitProviderAccountPresentationAction: Equatable {
    case signIn
    case add
    case edit
    case delete
}

enum GitProviderAddAccountHost: String, CaseIterable, Identifiable {
    case github
    case gitlab
    case bitbucket

    var id: Self { self }
}

enum GitProviderAddAccountAuthType: String, CaseIterable, Identifiable {
    case oauth
    case personalAccessToken

    var id: Self { self }
}

enum GitProviderAddAccountProtocol: String, CaseIterable, Identifiable {
    case https
    case ssh

    var id: Self { self }
}

struct GitProviderAddAccountOption<ID: Equatable>: Equatable {
    var id: ID
    var title: String
    var isEnabled: Bool
}

enum GitProviderAccountsPresentationPolicy {
    static func actions(
        isSignedIn: Bool,
        account: GitProviderAccount?
    ) -> [GitProviderAccountPresentationAction] {
        guard isSignedIn else { return [.signIn] }
        guard let account else { return [.add] }

        return [.edit, .delete]
    }

    static func normalizedSelfHostedGitLabHost(from value: String) -> GitProviderHost? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(" ") else {
            return nil
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let host = url.host(percentEncoded: false),
              !host.isEmpty,
              host.lowercased() != "gitlab.com" else {
            return nil
        }

        return GitProviderHost(kind: .gitlab, baseURL: url).normalized
    }
}

enum GitProviderAddAccountPresentationPolicy {
    static let hostOptions: [GitProviderAddAccountOption<GitProviderAddAccountHost>] = [
        GitProviderAddAccountOption(id: .github, title: "GitHub", isEnabled: true),
        GitProviderAddAccountOption(id: .gitlab, title: "GitLab", isEnabled: true),
        GitProviderAddAccountOption(id: .bitbucket, title: "Bitbucket", isEnabled: false)
    ]

    static let authTypeOptions: [GitProviderAddAccountOption<GitProviderAddAccountAuthType>] = [
        GitProviderAddAccountOption(id: .oauth, title: "OAuth", isEnabled: true),
        GitProviderAddAccountOption(id: .personalAccessToken, title: "Personal Access Token", isEnabled: false)
    ]

    static let protocolOptions: [GitProviderAddAccountOption<GitProviderAddAccountProtocol>] = [
        GitProviderAddAccountOption(id: .https, title: "HTTPS", isEnabled: true),
        GitProviderAddAccountOption(id: .ssh, title: "SSH", isEnabled: true)
    ]

    static func canConnect(
        host: GitProviderAddAccountHost,
        authType: GitProviderAddAccountAuthType,
        protocol selectedProtocol: GitProviderAddAccountProtocol
    ) -> Bool {
        host != .bitbucket && authType == .oauth
    }

    static func canSave(
        connectedUsername: String,
        protocol selectedProtocol: GitProviderAddAccountProtocol,
        sshKeyPath: String?
    ) -> Bool {
        guard !connectedUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard selectedProtocol == .ssh else {
            return true
        }
        return !(sshKeyPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func usernameDisplayText(for connectedUsername: String) -> String {
        connectedUsername.isEmpty ? "_" : connectedUsername
    }

    static func connectButtonTitle(connectedUsername: String) -> String {
        connectedUsername.isEmpty ? "Connect Account" : "Reconnect"
    }

    static func connectButtonTitle(
        connectedUsername: String,
        protocol selectedProtocol: GitProviderAddAccountProtocol
    ) -> String {
        guard selectedProtocol == .ssh else {
            return connectButtonTitle(connectedUsername: connectedUsername)
        }
        return connectedUsername.isEmpty ? "Test SSH Key" : "Test Again"
    }

    static func host(for account: GitProviderAccount) -> GitProviderAddAccountHost {
        switch account.provider {
        case .github: .github
        case .gitlab: .gitlab
        }
    }

    static func optionTitle<ID: Equatable>(
        for id: ID,
        in options: [GitProviderAddAccountOption<ID>]
    ) -> String {
        options.first { $0.id == id }?.title ?? ""
    }
}
