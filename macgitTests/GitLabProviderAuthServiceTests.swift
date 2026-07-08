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

import XCTest
@testable import macgit

final class GitLabProviderAuthServiceTests: XCTestCase {
    func testAuthorizationURLIncludesPKCEChallenge() throws {
        let service = makeService(httpClient: StubGitLabAuthHTTPClient())
        let session = makeSession()

        let url = try service.authorizationURL(for: session)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "gitlab.example.com")
        XCTAssertEqual(url.path, "/oauth/authorize")
        XCTAssertEqual(queryItems["client_id"], "gitlab-client-id")
        XCTAssertEqual(queryItems["redirect_uri"], "macgit://git-provider/oauth/callback")
        XCTAssertEqual(queryItems["response_type"], "code")
        XCTAssertEqual(queryItems["state"], "expected-state")
        XCTAssertEqual(queryItems["scope"], "api read_user")
        XCTAssertEqual(queryItems["code_challenge"], GitProviderPKCE.challenge(for: "fixed-code-verifier"))
        XCTAssertEqual(queryItems["code_challenge_method"], "S256")
    }

    func testTokenExchangeUsesConfiguredHost() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(
                statusCode: 200,
                body: #"{"access_token":"secret-token","refresh_token":"refresh-token","expires_in":7200,"token_type":"Bearer"}"#
            )
        ])
        let service = makeService(httpClient: client)

        let token = try await service.exchangeCallback(
            GitProviderOAuthCallback(code: "oauth-code", state: "expected-state"),
            session: makeSession()
        )

        let request = try XCTUnwrap(client.requests.first)
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://gitlab.example.com/oauth/token")
        XCTAssertTrue(body.contains("client_id=gitlab-client-id"))
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=oauth-code"))
        XCTAssertTrue(body.contains("redirect_uri=macgit://git-provider/oauth/callback"))
        XCTAssertTrue(body.contains("code_verifier=fixed-code-verifier"))
        XCTAssertFalse(body.contains("client_secret"))
        XCTAssertEqual(token.accessToken, "secret-token")
        XCTAssertEqual(token.refreshToken, "refresh-token")
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 1_700_007_200))
        XCTAssertEqual(token.tokenType, "Bearer")
    }

    func testProfileResponseCreatesGitLabProviderAccount() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(
                statusCode: 200,
                body: #"{"id":42,"username":"tanuki","name":"GitLab User","avatar_url":"https://gitlab.com/uploads/-/system/user/avatar/42/avatar.png"}"#
            )
        ])
        let service = makeService(httpClient: client)

        let account = try await service.fetchAccount(
            token: makeToken(),
            macgitUID: "macgit-user-1",
            host: .gitlabDotCom
        )

        XCTAssertEqual(account.id, "macgit-user-1:gitlab:gitlab.com:42")
        XCTAssertEqual(account.provider, .gitlab)
        XCTAssertEqual(account.hostURL, URL(string: "https://gitlab.com"))
        XCTAssertEqual(account.providerUserID, "42")
        XCTAssertEqual(account.username, "tanuki")
        XCTAssertEqual(account.displayName, "GitLab User")
        XCTAssertEqual(account.avatarURL?.absoluteString, "https://gitlab.com/uploads/-/system/user/avatar/42/avatar.png")
        XCTAssertEqual(account.tokenStatus, .valid)
        XCTAssertEqual(account.connectedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(account.lastValidatedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(client.requests.first?.url?.absoluteString, "https://gitlab.com/api/v4/user")
        XCTAssertEqual(client.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
    }

    func testSelfHostedHostIsPreserved() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(statusCode: 200, body: #"{"id":99,"username":"admin","name":null,"avatar_url":null}"#)
        ])
        let service = makeService(httpClient: client)
        let host = GitProviderHost(
            kind: .gitlab,
            baseURL: try XCTUnwrap(URL(string: "https://gitlab.example.com/gitlab/"))
        )

        let account = try await service.fetchAccount(
            token: makeToken(),
            macgitUID: "macgit-user-1",
            host: host
        )

        XCTAssertEqual(account.id, "macgit-user-1:gitlab:gitlab.example.com:99")
        XCTAssertEqual(account.hostURL.absoluteString, "https://gitlab.example.com")
        XCTAssertEqual(client.requests.first?.url?.absoluteString, "https://gitlab.example.com/api/v4/user")
    }

    func testUnauthorizedMapsToReauthorizationRequired() async throws {
        let client = StubGitLabAuthHTTPClient(responses: [
            .json(statusCode: 401, body: #"{"message":"401 Unauthorized"}"#)
        ])
        let service = makeService(httpClient: client)

        do {
            _ = try await service.fetchAccount(
                token: makeToken(),
                macgitUID: "macgit-user-1",
                host: .gitlabDotCom
            )
            XCTFail("Expected fetchAccount to throw")
        } catch {
            XCTAssertEqual(error as? GitProviderAuthError, .reauthorizationRequired)
        }
    }

    private func makeService(httpClient: GitProviderHTTPClient) -> GitLabProviderAuthService {
        GitLabProviderAuthService(
            configuration: GitLabProviderAuthConfiguration(
                clientID: "gitlab-client-id",
                redirectURI: URL(string: "macgit://git-provider/oauth/callback")!,
                scopes: ["api", "read_user"]
            ),
            httpClient: httpClient,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func makeSession() -> GitProviderOAuthSession {
        GitProviderOAuthSession(
            provider: .gitlab,
            host: GitProviderHost(
                kind: .gitlab,
                baseURL: URL(string: "https://gitlab.example.com")!
            ),
            state: "expected-state",
            codeVerifier: "fixed-code-verifier",
            redirectURI: URL(string: "macgit://git-provider/oauth/callback")!
        )
    }

    private func makeToken() -> GitProviderToken {
        GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "Bearer"
        )
    }
}

private final class StubGitLabAuthHTTPClient: GitProviderHTTPClient {
    struct Response {
        var statusCode: Int
        var data: Data

        static func json(statusCode: Int, body: String) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8))
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Response] = []) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let httpResponse = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: [:]
            )
        )
        return (response.data, httpResponse)
    }
}
