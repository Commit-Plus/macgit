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

enum GitProviderKind: String, Codable, CaseIterable, Identifiable {
    case github
    case gitlab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        }
    }
}

struct GitProviderHost: Hashable, Codable {
    var kind: GitProviderKind
    var baseURL: URL

    static let githubDotCom = GitProviderHost(
        kind: .github,
        baseURL: URL(string: "https://github.com")!
    )

    static let gitlabDotCom = GitProviderHost(
        kind: .gitlab,
        baseURL: URL(string: "https://gitlab.com")!
    )

    var normalized: GitProviderHost {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        if components?.scheme == nil {
            components?.scheme = "https"
        }
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return GitProviderHost(kind: kind, baseURL: components?.url ?? baseURL)
    }
}

enum GitProviderTokenStatus: String, Codable, Equatable {
    case valid
    case expired
    case revoked
    case reauthorizationRequired
    case unavailableOnThisDevice
}

enum GitProviderTransportProtocol: String, Codable, Equatable, CaseIterable, Identifiable {
    case https
    case ssh

    var id: String { rawValue }
}

struct GitProviderAccount: Identifiable, Equatable, Codable {
    var id: String
    var macgitUID: String
    var provider: GitProviderKind
    var hostURL: URL
    var providerUserID: String
    var username: String
    var displayName: String?
    var avatarURL: URL?
    var scopes: [String]
    var permissions: [String: String]
    var tokenStatus: GitProviderTokenStatus
    var transportProtocol: GitProviderTransportProtocol
    var connectedAt: Date
    var lastValidatedAt: Date?

    init(
        id: String,
        macgitUID: String,
        provider: GitProviderKind,
        hostURL: URL,
        providerUserID: String,
        username: String,
        displayName: String?,
        avatarURL: URL?,
        scopes: [String],
        permissions: [String: String],
        tokenStatus: GitProviderTokenStatus,
        transportProtocol: GitProviderTransportProtocol = .https,
        connectedAt: Date,
        lastValidatedAt: Date?
    ) {
        self.id = id
        self.macgitUID = macgitUID
        self.provider = provider
        self.hostURL = hostURL
        self.providerUserID = providerUserID
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.scopes = scopes
        self.permissions = permissions
        self.tokenStatus = tokenStatus
        self.transportProtocol = transportProtocol
        self.connectedAt = connectedAt
        self.lastValidatedAt = lastValidatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case macgitUID
        case provider
        case hostURL
        case providerUserID
        case username
        case displayName
        case avatarURL
        case scopes
        case permissions
        case tokenStatus
        case transportProtocol
        case connectedAt
        case lastValidatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        macgitUID = try container.decode(String.self, forKey: .macgitUID)
        provider = try container.decode(GitProviderKind.self, forKey: .provider)
        hostURL = try container.decode(URL.self, forKey: .hostURL)
        providerUserID = try container.decode(String.self, forKey: .providerUserID)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        scopes = try container.decode([String].self, forKey: .scopes)
        permissions = try container.decode([String: String].self, forKey: .permissions)
        tokenStatus = try container.decode(GitProviderTokenStatus.self, forKey: .tokenStatus)
        transportProtocol = try container.decodeIfPresent(
            GitProviderTransportProtocol.self,
            forKey: .transportProtocol
        ) ?? .https
        connectedAt = try container.decode(Date.self, forKey: .connectedAt)
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
    }
}

struct GitProviderToken: Equatable, Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var tokenType: String
}

struct GitRepositoryIdentity: Equatable, Codable {
    var provider: GitProviderKind
    var hostURL: URL
    var owner: String
    var name: String
}
