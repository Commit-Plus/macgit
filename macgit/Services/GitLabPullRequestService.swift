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

struct GitLabPullRequestService: PullRequestProviding {
    private let httpClient: GitProviderHTTPClient
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(httpClient: GitProviderHTTPClient = URLSessionGitProviderHTTPClient()) {
        self.httpClient = httpClient
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }

    func listPullRequests(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        filter: PullRequestListFilter,
        page: Int,
        perPage: Int
    ) async throws -> PullRequestListPage {
        guard repository.provider == .gitlab else {
            throw PullRequestProviderError.unsupportedProvider
        }
        let normalizedPage = max(1, page)
        let normalizedPerPage = min(max(1, perPage), 100)
        let url = try projectURL(
            repository: repository,
            pathComponents: ["merge_requests"],
            queryItems: [
                URLQueryItem(name: "state", value: filter.gitLabState),
                URLQueryItem(name: "per_page", value: String(normalizedPerPage)),
                URLQueryItem(name: "page", value: String(normalizedPage)),
            ]
        )

        let (data, response) = try await httpClient.data(for: makeRequest(url: url, token: token))
        try validate(response: response, data: data)
        do {
            let mergeRequests = try decoder.decode([GitLabMergeRequestResponse].self, from: data)
            return PullRequestListPage(
                items: mergeRequests.map(\.summary),
                page: normalizedPage,
                perPage: normalizedPerPage,
                hasPreviousPage: hasPaginationHeader("X-Prev-Page", in: response) || normalizedPage > 1,
                hasNextPage: hasPaginationHeader("X-Next-Page", in: response)
            )
        } catch {
            throw PullRequestProviderError.providerMessage("GitLab returned an invalid merge request response.")
        }
    }

    func pullRequestDetail(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> PullRequestDetail {
        guard repository.provider == .gitlab else {
            throw PullRequestProviderError.unsupportedProvider
        }

        let detailURL = try projectURL(
            repository: repository,
            pathComponents: ["merge_requests", String(number)]
        )
        let (detailData, detailResponse) = try await httpClient.data(for: makeRequest(url: detailURL, token: token))
        try validate(response: detailResponse, data: detailData)

        do {
            let response = try decoder.decode(GitLabMergeRequestDetailResponse.self, from: detailData)
            return PullRequestDetail(
                summary: response.mergeRequest.summary,
                body: response.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                assignees: response.assignees.map(\.author),
                comments: try await mergeRequestNotes(repository: repository, token: token, number: number),
                changesURL: response.mergeRequest.webURL.appendingPathComponent("diffs")
            )
        } catch let error as PullRequestProviderError {
            throw error
        } catch {
            throw PullRequestProviderError.providerMessage("GitLab returned an invalid merge request detail response.")
        }
    }

    func createPullRequest(
        _ draft: PullRequestDraft,
        token: GitProviderToken
    ) async throws -> PullRequestSummary {
        guard draft.repository.provider == .gitlab else {
            throw PullRequestProviderError.unsupportedProvider
        }
        let url = try projectURL(
            repository: draft.repository,
            pathComponents: ["merge_requests"]
        )
        let payload = GitLabCreateMergeRequestPayload(
            title: draft.title,
            description: draft.body.isEmpty ? nil : draft.body,
            sourceBranch: draft.sourceBranch,
            targetBranch: draft.targetBranch
        )

        do {
            let (data, response) = try await httpClient.data(
                for: try makeJSONRequest(url: url, token: token, method: "POST", body: payload)
            )
            try validateWrite(response: response, data: data)
            return try decoder.decode(GitLabMergeRequestResponse.self, from: data).summary
        } catch let error as PullRequestProviderError {
            throw error
        } catch {
            throw PullRequestProviderError.providerMessage("GitLab returned an invalid merge request response.")
        }
    }

    func createComment(
        body: String,
        on pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        guard repository.provider == .gitlab else {
            throw PullRequestProviderError.unsupportedProvider
        }
        let url = try projectURL(
            repository: repository,
            pathComponents: ["merge_requests", String(pullRequest.number), "notes"]
        )
        let payload = GitLabMergeRequestNotePayload(body: body)

        let (data, response) = try await httpClient.data(
            for: try makeJSONRequest(url: url, token: token, method: "POST", body: payload)
        )
        try validateWrite(response: response, data: data)
    }

    private func mergeRequestNotes(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> [PullRequestComment] {
        let notesURL = try projectURL(
            repository: repository,
            pathComponents: ["merge_requests", String(number), "notes"]
        )
        let (data, response) = try await httpClient.data(for: makeRequest(url: notesURL, token: token))
        try validate(response: response, data: data)
        return try decoder.decode([GitLabMergeRequestNoteResponse].self, from: data)
            .filter { !$0.system }
            .map(\.comment)
    }

    private func projectURL(
        repository: GitRepositoryIdentity,
        pathComponents: [String],
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        let projectPath = "\(repository.owner)/\(repository.name)"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encodedProjectPath = projectPath.addingPercentEncoding(withAllowedCharacters: allowed),
              var components = URLComponents(url: repository.hostURL, resolvingAgainstBaseURL: false) else {
            throw PullRequestProviderError.repositoryUnavailable
        }

        let suffix = pathComponents.map { "/\($0)" }.joined()
        components.percentEncodedPath = "/api/v4/projects/\(encodedProjectPath)\(suffix)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw PullRequestProviderError.repositoryUnavailable
        }
        return url
    }

    private func makeRequest(url: URL, token: GitProviderToken) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeJSONRequest<Body: Encodable>(
        url: URL,
        token: GitProviderToken,
        method: String,
        body: Body
    ) throws -> URLRequest {
        var request = makeRequest(url: url, token: token)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
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
            let message = (try? decoder.decode(GitLabErrorResponse.self, from: data).message)
                ?? "GitLab merge request request failed (HTTP \(response.statusCode))."
            throw PullRequestProviderError.providerMessage(message)
        }
    }

    private func validateWrite(response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 403:
            throw PullRequestProviderError.providerMessage(
                "The connected account does not have permission to modify merge requests."
            )
        default:
            try validate(response: response, data: data)
        }
    }

    private func hasPaginationHeader(_ name: String, in response: HTTPURLResponse) -> Bool {
        guard let value = response.value(forHTTPHeaderField: name) else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private extension PullRequestListFilter {
    var gitLabState: String {
        switch self {
        case .open:
            "opened"
        case .closed:
            "closed"
        case .all:
            "all"
        }
    }
}

private struct GitLabCreateMergeRequestPayload: Encodable {
    var title: String
    var description: String?
    var sourceBranch: String
    var targetBranch: String

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
    }
}

private struct GitLabMergeRequestNotePayload: Encodable {
    var body: String
}

private struct GitLabMergeRequestResponse: Decodable {
    var iid: Int
    var title: String
    var state: String
    var draft: Bool?
    var webURL: URL
    var createdAt: Date
    var updatedAt: Date
    var mergedAt: Date?
    var sourceBranch: String
    var targetBranch: String
    var sha: String?
    var author: User

    var summary: PullRequestSummary {
        PullRequestSummary(
            number: iid,
            title: title,
            state: pullRequestState,
            author: author.author,
            source: PullRequestBranchRef(label: sourceBranch, ref: sourceBranch, sha: sha),
            target: PullRequestBranchRef(label: targetBranch, ref: targetBranch, sha: nil),
            webURL: webURL,
            createdAt: createdAt,
            updatedAt: updatedAt,
            mergedAt: mergedAt
        )
    }

    private var pullRequestState: PullRequestState {
        if draft == true {
            return .draft
        }
        switch state {
        case "merged":
            return .merged
        case "closed":
            return .closed
        default:
            return .open
        }
    }

    enum CodingKeys: String, CodingKey {
        case iid
        case title
        case state
        case draft
        case webURL = "web_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case sha
        case author
    }

    struct User: Decodable {
        var username: String
        var avatarURL: URL?

        var author: PullRequestAuthor {
            PullRequestAuthor(username: username, avatarURL: avatarURL)
        }

        enum CodingKeys: String, CodingKey {
            case username
            case avatarURL = "avatar_url"
        }
    }
}

private struct GitLabMergeRequestDetailResponse: Decodable {
    var mergeRequest: GitLabMergeRequestResponse
    var description: String?
    var assignees: [GitLabMergeRequestResponse.User]

    init(from decoder: Decoder) throws {
        mergeRequest = try GitLabMergeRequestResponse(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        assignees = try container.decodeIfPresent([GitLabMergeRequestResponse.User].self, forKey: .assignees) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case description
        case assignees
    }
}

private struct GitLabMergeRequestNoteResponse: Decodable {
    var id: Int
    var body: String
    var system: Bool
    var webURL: URL
    var createdAt: Date
    var updatedAt: Date
    var author: GitLabMergeRequestResponse.User

    var comment: PullRequestComment {
        PullRequestComment(
            id: id,
            author: author.author,
            body: body,
            webURL: webURL,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case system
        case webURL = "web_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case author
    }
}

private struct GitLabErrorResponse: Decodable {
    var message: String
}
