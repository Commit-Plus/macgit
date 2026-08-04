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

@MainActor
final class RepositoryVisibilityServiceTests: XCTestCase {
    func testGitHubPublicRepositoryUsesAnonymousAPIRequest() async throws {
        let client = StubRepositoryVisibilityHTTPClient(
            responses: [.json(statusCode: 200, body: #"{"private":false}"#)]
        )
        let service = GitHubRepositoryVisibilityService(httpClient: client)

        let visibility = try await service.visibility(for: githubRepository, token: nil)

        XCTAssertEqual(visibility, .public)
        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "https://api.github.com/repos/octocat/Hello-World"
        )
        XCTAssertNil(client.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testGitHubPrivateRepositoryUsesBearerToken() async throws {
        let client = StubRepositoryVisibilityHTTPClient(
            responses: [.json(statusCode: 200, body: #"{"private":true}"#)]
        )
        let service = GitHubRepositoryVisibilityService(httpClient: client)

        let visibility = try await service.visibility(
            for: githubRepository,
            token: token
        )

        XCTAssertEqual(visibility, .private)
        XCTAssertEqual(
            client.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer secret-token"
        )
    }

    func testGitLabNestedPublicProjectUsesEncodedProjectPath() async throws {
        let client = StubRepositoryVisibilityHTTPClient(
            responses: [.json(statusCode: 200, body: #"{"visibility":"public"}"#)]
        )
        let service = GitLabRepositoryVisibilityService(httpClient: client)
        let repository = GitRepositoryIdentity(
            provider: .gitlab,
            hostURL: URL(string: "https://gitlab.example.com")!,
            owner: "group/subgroup",
            name: "project"
        )

        let visibility = try await service.visibility(for: repository, token: nil)

        XCTAssertEqual(visibility, .public)
        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "https://gitlab.example.com/api/v4/projects/group%2Fsubgroup%2Fproject"
        )
    }

    func testGitLabInternalProjectIsRestrictedLikePrivate() async throws {
        let client = StubRepositoryVisibilityHTTPClient(
            responses: [.json(statusCode: 200, body: #"{"visibility":"internal"}"#)]
        )

        let visibility = try await GitLabRepositoryVisibilityService(httpClient: client)
            .visibility(for: gitLabRepository, token: token)

        XCTAssertEqual(visibility, .private)
    }

    func testProviderErrorsDoNotInventVisibility() async {
        let client = StubRepositoryVisibilityHTTPClient(
            responses: [.json(statusCode: 404, body: "{}")]
        )

        do {
            _ = try await GitHubRepositoryVisibilityService(httpClient: client)
                .visibility(for: githubRepository, token: nil)
            XCTFail("Expected repositoryUnavailable")
        } catch {
            XCTAssertEqual(error as? RepositoryVisibilityProviderError, .repositoryUnavailable)
        }
    }

    private var githubRepository: GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            owner: "octocat",
            name: "Hello-World"
        )
    }

    private var gitLabRepository: GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .gitlab,
            hostURL: URL(string: "https://gitlab.com")!,
            owner: "group",
            name: "project"
        )
    }

    private var token: GitProviderToken {
        GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "bearer"
        )
    }
}

private final class StubRepositoryVisibilityHTTPClient: GitProviderHTTPClient {
    struct Response {
        let statusCode: Int
        let data: Data

        static func json(statusCode: Int, body: String) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8))
        }
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        return (
            response.data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
