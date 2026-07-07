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

final class GitHubPullRequestServiceTests: XCTestCase {
    func testListPullRequestsDecodesOpenGitHubPRs() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "number": 12,
                "title": "Add provider-backed pull request read",
                "state": "open",
                "draft": false,
                "html_url": "https://github.com/octocat/Hello-World/pull/12",
                "updated_at": "2026-07-06T10:11:12Z",
                "user": {
                  "login": "octocat",
                  "avatar_url": "https://avatars.githubusercontent.com/u/1"
                },
                "head": {
                  "label": "octocat:feature/pr-read",
                  "ref": "feature/pr-read",
                  "sha": "abc123"
                },
                "base": {
                  "label": "octocat:main",
                  "ref": "main",
                  "sha": "def456"
                }
              }
            ]
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let pullRequests = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken()
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.github.com/repos/octocat/Hello-World/pulls?state=open"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(pullRequests.count, 1)
        XCTAssertEqual(pullRequests[0].number, 12)
        XCTAssertEqual(pullRequests[0].title, "Add provider-backed pull request read")
        XCTAssertEqual(pullRequests[0].state, .open)
        XCTAssertEqual(pullRequests[0].author.username, "octocat")
        XCTAssertEqual(pullRequests[0].author.avatarURL?.absoluteString, "https://avatars.githubusercontent.com/u/1")
        XCTAssertEqual(pullRequests[0].source.ref, "feature/pr-read")
        XCTAssertEqual(pullRequests[0].target.ref, "main")
        XCTAssertEqual(pullRequests[0].webURL.absoluteString, "https://github.com/octocat/Hello-World/pull/12")
        XCTAssertEqual(pullRequests[0].updatedAt, ISO8601DateFormatter().date(from: "2026-07-06T10:11:12Z"))
    }

    func testDraftGitHubPRDecodesAsDraftState() async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "number": 13,
                "title": "Draft pull request",
                "state": "open",
                "draft": true,
                "html_url": "https://github.com/octocat/Hello-World/pull/13",
                "updated_at": "2026-07-06T10:11:12Z",
                "user": { "login": "octocat", "avatar_url": null },
                "head": { "label": "octocat:draft", "ref": "draft", "sha": null },
                "base": { "label": "octocat:main", "ref": "main", "sha": "def456" }
              }
            ]
            """)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        let pullRequests = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken()
        )

        XCTAssertEqual(pullRequests[0].state, .draft)
    }

    func testUnauthorizedMapsToReauthorizationRequired() async throws {
        try await assertStatus(
            401,
            mapsTo: .reauthorizationRequired
        )
    }

    func testForbiddenMapsToPermissionDenied() async throws {
        try await assertStatus(
            403,
            mapsTo: .permissionDenied
        )
    }

    func testNotFoundMapsToRepositoryUnavailable() async throws {
        try await assertStatus(
            404,
            mapsTo: .repositoryUnavailable
        )
    }

    private func assertStatus(
        _ statusCode: Int,
        mapsTo expectedError: PullRequestProviderError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let client = StubPullRequestHTTPClient(responses: [
            .json(statusCode: statusCode, body: #"{"message":"request failed"}"#)
        ])
        let service = GitHubPullRequestService(httpClient: client)

        do {
            _ = try await service.listPullRequests(repository: makeRepository(), token: makeToken())
            XCTFail("Expected listPullRequests to throw", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? PullRequestProviderError, expectedError, file: file, line: line)
        }
    }

    private func makeRepository() -> GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            owner: "octocat",
            name: "Hello-World"
        )
    }

    private func makeToken() -> GitProviderToken {
        GitProviderToken(
            accessToken: "secret-token",
            refreshToken: nil,
            expiresAt: nil,
            tokenType: "bearer"
        )
    }
}

private final class StubPullRequestHTTPClient: GitProviderHTTPClient {
    struct Response {
        var statusCode: Int
        var data: Data

        static func json(statusCode: Int, body: String) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8))
        }
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Response]

    init(responses: [Response]) {
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
                headerFields: nil
            )
        )
        return (response.data, httpResponse)
    }
}
