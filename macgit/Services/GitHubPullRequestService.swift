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

struct GitHubPullRequestService: PullRequestProviding {
    private let httpClient: GitProviderHTTPClient
    private let apiBaseURL: URL
    private let decoder: JSONDecoder

    init(
        httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient(),
        apiBaseURL: URL = URL(string: "https://api.github.com")!
    ) {
        self.httpClient = httpClient
        self.apiBaseURL = apiBaseURL
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func listPullRequests(
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws -> [PullRequestSummary] {
        guard repository.provider == .github else {
            throw PullRequestProviderError.unsupportedProvider
        }

        var components = URLComponents(
            url: apiBaseURL
                .appendingPathComponent("repos")
                .appendingPathComponent(repository.owner)
                .appendingPathComponent(repository.name)
                .appendingPathComponent("pulls"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "state", value: "open")]
        guard let url = components?.url else {
            throw PullRequestProviderError.repositoryUnavailable
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)
        do {
            return try decoder.decode([GitHubPullRequestResponse].self, from: data)
                .map(\.summary)
        } catch {
            throw PullRequestProviderError.providerMessage("GitHub returned an invalid pull request response.")
        }
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw PullRequestProviderError.reauthorizationRequired
        case 403:
            throw PullRequestProviderError.permissionDenied
        case 404:
            throw PullRequestProviderError.repositoryUnavailable
        default:
            let message = (try? decoder.decode(GitHubErrorResponse.self, from: data).message)
                ?? "GitHub pull request request failed (HTTP \(response.statusCode))."
            throw PullRequestProviderError.providerMessage(message)
        }
    }
}

private struct GitHubPullRequestResponse: Decodable {
    var number: Int
    var title: String
    var state: String
    var draft: Bool
    var htmlURL: URL
    var updatedAt: Date
    var user: User
    var head: Branch
    var base: Branch

    var summary: PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: title,
            state: pullRequestState,
            author: PullRequestAuthor(username: user.login, avatarURL: user.avatarURL),
            source: head.summaryRef,
            target: base.summaryRef,
            webURL: htmlURL,
            updatedAt: updatedAt
        )
    }

    private var pullRequestState: PullRequestState {
        if draft {
            return .draft
        }
        switch state {
        case "closed":
            return .closed
        default:
            return .open
        }
    }

    private enum CodingKeys: String, CodingKey {
        case number
        case title
        case state
        case draft
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
        case user
        case head
        case base
    }

    struct User: Decodable {
        var login: String
        var avatarURL: URL?

        private enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }

    struct Branch: Decodable {
        var label: String
        var ref: String
        var sha: String?

        var summaryRef: PullRequestBranchRef {
            PullRequestBranchRef(label: label, ref: ref, sha: sha)
        }
    }
}

private struct GitHubErrorResponse: Decodable {
    var message: String
}
