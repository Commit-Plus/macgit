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

protocol GitProviderAuthenticating {
    func authorizationURL(for session: GitProviderOAuthSession) throws -> URL
    func exchangeCallback(
        _ callback: GitProviderOAuthCallback,
        session: GitProviderOAuthSession
    ) async throws -> GitProviderToken
    func fetchAccount(
        token: GitProviderToken,
        macgitUID: String,
        host: GitProviderHost
    ) async throws -> GitProviderAccount
}

protocol GitProviderHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionGitProviderHTTPClient: GitProviderHTTPClient {
    var session: URLSession = .shared

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitProviderAuthError.invalidResponse
        }
        return (data, response)
    }
}

struct GitHubProviderAuthConfiguration: Equatable {
    var clientID: String
    var redirectURI: URL
    var scopes: [String]
}

enum GitProviderAuthError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidResponse
    case reauthorizationRequired
    case providerMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "GitHub account connection is not configured."
        case .invalidResponse:
            "The Git provider returned an invalid response."
        case .reauthorizationRequired:
            "The Git provider account needs to be connected again."
        case .providerMessage(let message):
            message
        }
    }
}

struct GitHubProviderAuthService: GitProviderAuthenticating {
    private let configuration: GitHubProviderAuthConfiguration
    private let httpClient: GitProviderHTTPClient
    private let authorizationEndpoint: URL
    private let tokenEndpoint: URL
    private let apiBaseURL: URL
    private let now: () -> Date

    init(
        configuration: GitHubProviderAuthConfiguration,
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        authorizationEndpoint: URL = URL(string: "https://github.com/login/oauth/authorize")!,
        tokenEndpoint: URL = URL(string: "https://github.com/login/oauth/access_token")!,
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.apiBaseURL = apiBaseURL
        self.now = now
    }

    func authorizationURL(for session: GitProviderOAuthSession) throws -> URL {
        guard !configuration.clientID.isEmpty,
              session.provider == .github,
              session.redirectURI == configuration.redirectURI else {
            throw GitProviderAuthError.invalidConfiguration
        }

        guard var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw GitProviderAuthError.invalidConfiguration
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "state", value: session.state),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: GitProviderPKCE.challenge(for: session.codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components.url else {
            throw GitProviderAuthError.invalidConfiguration
        }
        return url
    }

    func exchangeCallback(
        _ callback: GitProviderOAuthCallback,
        session: GitProviderOAuthSession
    ) async throws -> GitProviderToken {
        guard callback.state == session.state else {
            throw GitProviderOAuthError.stateMismatch
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "code", value: callback.code),
            URLQueryItem(name: "redirect_uri", value: session.redirectURI.absoluteString),
            URLQueryItem(name: "code_verifier", value: session.codeVerifier)
        ])

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)
        let payload: TokenResponse
        do {
            payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GitProviderAuthError.invalidResponse
        }

        return GitProviderToken(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: payload.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) },
            tokenType: payload.tokenType
        )
    }

    func fetchAccount(
        token: GitProviderToken,
        macgitUID: String,
        host: GitProviderHost
    ) async throws -> GitProviderAccount {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("user"))
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)
        let profile: UserResponse
        do {
            profile = try JSONDecoder().decode(UserResponse.self, from: data)
        } catch {
            throw GitProviderAuthError.invalidResponse
        }

        let timestamp = now()
        let normalizedHost = host.normalized.baseURL
        let hostIdentifier = normalizedHost.host?.lowercased() ?? normalizedHost.absoluteString.lowercased()
        let scopes = response.value(forHTTPHeaderField: "X-OAuth-Scopes")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return GitProviderAccount(
            id: "\(macgitUID):github:\(hostIdentifier):\(profile.id)",
            macgitUID: macgitUID,
            provider: .github,
            hostURL: normalizedHost,
            providerUserID: String(profile.id),
            username: profile.login,
            displayName: profile.name,
            avatarURL: profile.avatarURL,
            scopes: scopes,
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: timestamp,
            lastValidatedAt: timestamp
        )
    }

    private func formEncoded(_ queryItems: [URLQueryItem]) -> Data? {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        if response.statusCode == 401 {
            throw GitProviderAuthError.reauthorizationRequired
        }
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw GitProviderAuthError.providerMessage(
                payload?.errorDescription ?? payload?.message ?? "GitHub request failed (HTTP \(response.statusCode))."
            )
        }
    }
}

private extension GitHubProviderAuthService {
    struct TokenResponse: Decodable {
        var accessToken: String
        var refreshToken: String?
        var expiresIn: Int?
        var tokenType: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }

    struct UserResponse: Decodable {
        var id: Int64
        var login: String
        var name: String?
        var avatarURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case login
            case name
            case avatarURL = "avatar_url"
        }
    }

    struct ErrorResponse: Decodable {
        var message: String?
        var errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case message
            case errorDescription = "error_description"
        }
    }
}
