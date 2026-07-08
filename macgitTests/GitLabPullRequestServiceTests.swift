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

final class GitLabPullRequestServiceTests: XCTestCase {
    func testListMergeRequestsDecodesOpenItems() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: """
            [
              {
                "iid": 7,
                "title": "Add GitLab merge requests",
                "state": "opened",
                "draft": false,
                "web_url": "https://gitlab.com/group/subgroup/project/-/merge_requests/7",
                "created_at": "2026-07-01T09:10:11Z",
                "updated_at": "2026-07-06T10:11:12Z",
                "merged_at": null,
                "source_branch": "feature/gitlab-mrs",
                "target_branch": "main",
                "sha": "abc123",
                "author": {
                  "username": "tanuki",
                  "avatar_url": "https://gitlab.com/uploads/-/system/user/avatar/42/avatar.png"
                }
              }
            ]
            """, headers: [
                "X-Next-Page": "2"
            ])
        ])
        let service = GitLabPullRequestService(httpClient: client)

        let page = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken(),
            filter: .open,
            page: 1,
            perPage: 30
        )
        let mergeRequests = page.items

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests?state=opened&per_page=30&page=1"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(mergeRequests.count, 1)
        XCTAssertEqual(mergeRequests[0].number, 7)
        XCTAssertEqual(mergeRequests[0].title, "Add GitLab merge requests")
        XCTAssertEqual(mergeRequests[0].state, .open)
        XCTAssertEqual(mergeRequests[0].author.username, "tanuki")
        XCTAssertEqual(mergeRequests[0].source.ref, "feature/gitlab-mrs")
        XCTAssertEqual(mergeRequests[0].source.sha, "abc123")
        XCTAssertEqual(mergeRequests[0].target.ref, "main")
        XCTAssertEqual(mergeRequests[0].webURL.absoluteString, "https://gitlab.com/group/subgroup/project/-/merge_requests/7")
        XCTAssertTrue(page.hasNextPage)
        XCTAssertFalse(page.hasPreviousPage)
    }

    func testCreateMergeRequestPostsExpectedBody() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 201, body: """
            {
              "iid": 8,
              "title": "Add GitLab action",
              "state": "opened",
              "draft": false,
              "web_url": "https://gitlab.com/group/subgroup/project/-/merge_requests/8",
              "created_at": "2026-07-08T00:10:11Z",
              "updated_at": "2026-07-08T00:10:11Z",
              "merged_at": null,
              "source_branch": "feature/gitlab-action",
              "target_branch": "main",
              "sha": "def456",
              "author": { "username": "tanuki", "avatar_url": null }
            }
            """)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        let summary = try await service.createPullRequest(
            makeDraft(),
            token: makeToken()
        )

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["title"], "Add GitLab action")
        XCTAssertEqual(json["description"], "Implements GitLab merge request actions.")
        XCTAssertEqual(json["source_branch"], "feature/gitlab-action")
        XCTAssertEqual(json["target_branch"], "main")
        XCTAssertEqual(summary.number, 8)
        XCTAssertEqual(summary.title, "Add GitLab action")
    }

    func testRepositoryPathIsURLEncodedForSubgroups() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 200, body: "[]")
        ])
        let service = GitLabPullRequestService(httpClient: client)

        _ = try await service.listPullRequests(
            repository: makeRepository(),
            token: makeToken(),
            filter: .all,
            page: 3,
            perPage: 25
        )

        XCTAssertEqual(
            client.requests.first?.url?.absoluteString,
            "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/merge_requests?state=all&per_page=25&page=3"
        )
    }

    func testForbiddenMapsToPermissionDenied() async throws {
        let client = StubGitLabPullRequestHTTPClient(responses: [
            .json(statusCode: 403, body: #"{"message":"403 Forbidden"}"#)
        ])
        let service = GitLabPullRequestService(httpClient: client)

        do {
            _ = try await service.listPullRequests(
                repository: makeRepository(),
                token: makeToken(),
                filter: .open,
                page: 1,
                perPage: 30
            )
            XCTFail("Expected listPullRequests to throw")
        } catch {
            XCTAssertEqual(error as? PullRequestProviderError, .permissionDenied)
        }
    }

    private func makeRepository() -> GitRepositoryIdentity {
        GitRepositoryIdentity(
            provider: .gitlab,
            hostURL: URL(string: "https://gitlab.com")!,
            owner: "group/subgroup",
            name: "project"
        )
    }

    private func makeDraft() throws -> PullRequestDraft {
        try PullRequestDraft(
            repository: makeRepository(),
            sourceBranch: "feature/gitlab-action",
            targetBranch: "main",
            title: "Add GitLab action",
            body: "Implements GitLab merge request actions."
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

private final class StubGitLabPullRequestHTTPClient: GitProviderHTTPClient {
    struct Response {
        var statusCode: Int
        var data: Data
        var headers: [String: String]

        static func json(statusCode: Int, body: String, headers: [String: String] = [:]) -> Response {
            Response(statusCode: statusCode, data: Data(body.utf8), headers: headers)
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
                headerFields: response.headers
            )
        )
        return (response.data, httpResponse)
    }
}
