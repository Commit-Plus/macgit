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

struct GitRemoteIdentity: Equatable {
    var provider: GitProviderKind
    var hostURL: URL
    var ownerPath: String
    var repositoryName: String
    var canonicalHTTPSURL: URL
}

enum GitRemoteIdentityResolver {
    static func identity(
        from remoteURLString: String,
        knownGitLabHosts: Set<String> = []
    ) -> GitRemoteIdentity? {
        let trimmed = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalizedKnownGitLabHosts = Set(knownGitLabHosts.map { $0.lowercased() })
        if let sshIdentity = identityFromScpLikeURL(trimmed, knownGitLabHosts: normalizedKnownGitLabHosts) {
            return sshIdentity
        }
        guard let url = URL(string: trimmed),
              let host = url.host(percentEncoded: false) else {
            return nil
        }
        return identity(
            host: host,
            pathComponents: url.pathComponents,
            knownGitLabHosts: normalizedKnownGitLabHosts
        )
    }

    private static func identityFromScpLikeURL(
        _ remoteURLString: String,
        knownGitLabHosts: Set<String>
    ) -> GitRemoteIdentity? {
        guard let atIndex = remoteURLString.firstIndex(of: "@"),
              let colonIndex = remoteURLString[atIndex...].firstIndex(of: ":") else {
            return nil
        }

        let hostStart = remoteURLString.index(after: atIndex)
        let host = String(remoteURLString[hostStart..<colonIndex])
        let pathStart = remoteURLString.index(after: colonIndex)
        let path = String(remoteURLString[pathStart...])
        let pathComponents = path.split(separator: "/").map(String.init)
        return identity(host: host, pathComponents: pathComponents, knownGitLabHosts: knownGitLabHosts)
    }

    private static func identity(
        host: String,
        pathComponents rawPathComponents: [String],
        knownGitLabHosts: Set<String>
    ) -> GitRemoteIdentity? {
        let normalizedHost = host.lowercased()
        guard let provider = provider(for: normalizedHost, knownGitLabHosts: knownGitLabHosts) else { return nil }

        let pathComponents = rawPathComponents
            .filter { $0 != "/" }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
        guard pathComponents.count >= 2 else { return nil }

        let repositoryName = strippingGitSuffix(pathComponents.last ?? "")
        guard !repositoryName.isEmpty else { return nil }

        let ownerComponents = Array(pathComponents.dropLast())
        if provider == .github, ownerComponents.count != 1 {
            return nil
        }

        let ownerPath = ownerComponents.joined(separator: "/")
        guard !ownerPath.isEmpty,
              let hostURL = URL(string: "https://\(normalizedHost)") else {
            return nil
        }

        let canonicalPath = (ownerComponents + [repositoryName + ".git"]).joined(separator: "/")
        guard let canonicalURL = URL(string: "https://\(normalizedHost)/\(canonicalPath)") else {
            return nil
        }

        return GitRemoteIdentity(
            provider: provider,
            hostURL: hostURL,
            ownerPath: ownerPath,
            repositoryName: repositoryName,
            canonicalHTTPSURL: canonicalURL
        )
    }

    private static func provider(for host: String, knownGitLabHosts: Set<String>) -> GitProviderKind? {
        switch host {
        case "github.com":
            return .github
        case "gitlab.com":
            return .gitlab
        default:
            return knownGitLabHosts.contains(host) || host.contains("gitlab") ? .gitlab : nil
        }
    }

    private static func strippingGitSuffix(_ value: String) -> String {
        if value.lowercased().hasSuffix(".git") {
            return String(value.dropLast(4))
        }
        return value
    }
}
