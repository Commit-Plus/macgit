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
        token: GitProviderToken,
        filter: PullRequestListFilter,
        page: Int,
        perPage: Int
    ) async throws -> PullRequestListPage {
        guard repository.provider == .github else {
            throw PullRequestProviderError.unsupportedProvider
        }
        let normalizedPage = max(1, page)
        let normalizedPerPage = min(max(1, perPage), 100)

        var components = URLComponents(
            url: apiBaseURL
                .appendingPathComponent("repos")
                .appendingPathComponent(repository.owner)
                .appendingPathComponent(repository.name)
                .appendingPathComponent("pulls"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "state", value: filter.apiState),
            URLQueryItem(name: "per_page", value: String(normalizedPerPage)),
            URLQueryItem(name: "page", value: String(normalizedPage)),
        ]
        guard let url = components?.url else {
            throw PullRequestProviderError.repositoryUnavailable
        }

        let request = makeRequest(url: url, token: token)

        let (data, response) = try await httpClient.data(for: request)
        try validate(response: response, data: data)
        do {
            let responses = try decoder.decode([GitHubPullRequestResponse].self, from: data)
            var summaries: [PullRequestSummary] = []
            for response in responses {
                summaries.append(await enrichedSummary(
                    response.summary,
                    repository: repository,
                    token: token
                ))
            }
            return PullRequestListPage(
                items: summaries,
                page: normalizedPage,
                perPage: normalizedPerPage,
                hasPreviousPage: hasLinkRelation("prev", in: response) || normalizedPage > 1,
                hasNextPage: hasLinkRelation("next", in: response)
            )
        } catch {
            throw PullRequestProviderError.providerMessage("GitHub returned an invalid pull request response.")
        }
    }

    func pullRequestDetail(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> PullRequestDetail {
        guard repository.provider == .github else {
            throw PullRequestProviderError.unsupportedProvider
        }

        let detailURL = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("pulls")
            .appendingPathComponent(String(number))
        let (detailData, detailResponse) = try await httpClient.data(for: makeRequest(url: detailURL, token: token))
        try validate(response: detailResponse, data: detailData)

        do {
            let response = try decoder.decode(GitHubPullRequestDetailPayload.self, from: detailData)
            return PullRequestDetail(
                summary: response.summary,
                body: response.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                assignees: response.assignees.map(\.author),
                comments: try await pullRequestComments(repository: repository, token: token, number: number),
                changesURL: response.changesURL
            )
        } catch let error as PullRequestProviderError {
            throw error
        } catch {
            throw PullRequestProviderError.providerMessage("GitHub returned an invalid pull request detail response.")
        }
    }

    func createPullRequest(
        _ draft: PullRequestDraft,
        token: GitProviderToken
    ) async throws -> PullRequestSummary {
        guard draft.repository.provider == .github else {
            throw PullRequestProviderError.unsupportedProvider
        }

        let url = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(draft.repository.owner)
            .appendingPathComponent(draft.repository.name)
            .appendingPathComponent("pulls")
        let payload = GitHubCreatePullRequestPayload(
            title: draft.title,
            body: draft.body.isEmpty ? nil : draft.body,
            head: draft.sourceBranch,
            base: draft.targetBranch
        )

        do {
            let (data, response) = try await httpClient.data(
                for: try makeJSONRequest(url: url, token: token, method: "POST", body: payload)
            )
            try validateWrite(response: response, data: data)
            let created = try decoder.decode(GitHubPullRequestResponse.self, from: data)
            return created.summary
        } catch let error as PullRequestProviderError {
            throw error
        } catch {
            throw PullRequestProviderError.providerMessage("GitHub returned an invalid pull request response.")
        }
    }

    func createComment(
        body: String,
        on pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        guard repository.provider == .github else {
            throw PullRequestProviderError.unsupportedProvider
        }

        let url = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("issues")
            .appendingPathComponent(String(pullRequest.number))
            .appendingPathComponent("comments")
        let payload = GitHubIssueCommentCreatePayload(body: body)

        let (data, response) = try await httpClient.data(
            for: try makeJSONRequest(url: url, token: token, method: "POST", body: payload)
        )
        try validateWrite(response: response, data: data)
    }

    private func issueComments(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> [PullRequestComment] {
        let commentsURL = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("issues")
            .appendingPathComponent(String(number))
            .appendingPathComponent("comments")
        let (data, response) = try await httpClient.data(for: makeRequest(url: commentsURL, token: token))
        try validate(response: response, data: data)
        return try decoder.decode([GitHubIssueCommentResponse].self, from: data)
            .map(\.comment)
    }

    private func pullRequestComments(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> [PullRequestComment] {
        var comments = try await issueComments(repository: repository, token: token, number: number)
        comments.append(contentsOf: try await pullRequestReviews(repository: repository, token: token, number: number))
        comments.append(contentsOf: try await pullRequestReviewComments(repository: repository, token: token, number: number))
        return comments.sorted { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }
    }

    private func pullRequestReviews(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> [PullRequestComment] {
        let reviewsURL = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("pulls")
            .appendingPathComponent(String(number))
            .appendingPathComponent("reviews")
        let (data, response) = try await httpClient.data(for: makeRequest(url: reviewsURL, token: token))
        try validate(response: response, data: data)
        return try decoder.decode([GitHubPullRequestReviewResponse].self, from: data)
            .compactMap(\.comment)
    }

    private func pullRequestReviewComments(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> [PullRequestComment] {
        let commentsURL = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("pulls")
            .appendingPathComponent(String(number))
            .appendingPathComponent("comments")
        let (data, response) = try await httpClient.data(for: makeRequest(url: commentsURL, token: token))
        try validate(response: response, data: data)
        return try decoder.decode([GitHubReviewCommentResponse].self, from: data)
            .map(\.comment)
    }

    private func enrichedSummary(
        _ summary: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async -> PullRequestSummary {
        var enriched = summary
        enriched.checkState = await checkState(
            for: summary,
            repository: repository,
            token: token
        )
        enriched.mergeReadiness = await mergeReadiness(
            for: summary,
            repository: repository,
            token: token
        )
        return enriched
    }

    private func checkState(
        for summary: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async -> PullRequestCheckState {
        guard let sha = summary.source.sha, !sha.isEmpty else {
            return .unknown
        }
        let url = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("commits")
            .appendingPathComponent(sha)
            .appendingPathComponent("status")
        do {
            let (data, response) = try await httpClient.data(for: makeRequest(url: url, token: token))
            guard (200..<300).contains(response.statusCode) else { return .unknown }
            let status = try decoder.decode(GitHubCombinedStatusResponse.self, from: data)
            guard status.totalCount > 0 else {
                return await checkRunState(sha: sha, repository: repository, token: token)
            }
            return PullRequestCheckState(githubStatus: status.state)
        } catch {
            return .unknown
        }
    }

    private func checkRunState(
        sha: String,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async -> PullRequestCheckState {
        let url = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("commits")
            .appendingPathComponent(sha)
            .appendingPathComponent("check-runs")
        do {
            let (data, response) = try await httpClient.data(for: makeRequest(url: url, token: token))
            guard (200..<300).contains(response.statusCode) else { return .unknown }
            let checkRuns = try decoder.decode(GitHubCheckRunsResponse.self, from: data)
            guard checkRuns.totalCount > 0 else { return .noChecks }
            return PullRequestCheckState(checkRuns: checkRuns.checkRuns)
        } catch {
            return .unknown
        }
    }

    private func mergeReadiness(
        for summary: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async -> PullRequestMergeReadiness {
        guard summary.state == .open else {
            return .unknown
        }
        let url = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(repository.owner)
            .appendingPathComponent(repository.name)
            .appendingPathComponent("pulls")
            .appendingPathComponent(String(summary.number))
        do {
            let (data, response) = try await httpClient.data(for: makeRequest(url: url, token: token))
            guard (200..<300).contains(response.statusCode) else { return .unknown }
            let detail = try decoder.decode(GitHubPullRequestDetailResponse.self, from: data)
            guard let mergeable = detail.mergeable else { return .unknown }
            return mergeable ? .ready : .blocked
        } catch {
            return .unknown
        }
    }

    private func makeRequest(url: URL, token: GitProviderToken) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func hasLinkRelation(_ relation: String, in response: HTTPURLResponse) -> Bool {
        guard let linkHeader = response.value(forHTTPHeaderField: "Link") else {
            return false
        }
        return linkHeader
            .split(separator: ",")
            .contains { segment in
                segment.range(of: "rel=\"\(relation)\"") != nil
            }
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
        request.httpBody = try JSONEncoder().encode(body)
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
            let message = (try? decoder.decode(GitHubErrorResponse.self, from: data).message)
                ?? "GitHub pull request request failed (HTTP \(response.statusCode))."
            throw PullRequestProviderError.providerMessage(message)
        }
    }

    private func validateWrite(response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 403:
            throw PullRequestProviderError.providerMessage(
                "The connected account does not have permission to modify pull requests."
            )
        default:
            try validate(response: response, data: data)
        }
    }
}

private struct GitHubCreatePullRequestPayload: Encodable {
    var title: String
    var body: String?
    var head: String
    var base: String
}

private struct GitHubIssueCommentCreatePayload: Encodable {
    var body: String
}

private struct GitHubPullRequestResponse: Decodable {
    var number: Int
    var title: String
    var state: String
    var draft: Bool
    var htmlURL: URL
    var createdAt: Date
    var updatedAt: Date
    var mergedAt: Date?
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
            createdAt: createdAt,
            updatedAt: updatedAt,
            mergedAt: mergedAt
        )
    }

    private var pullRequestState: PullRequestState {
        if draft {
            return .draft
        }
        switch state {
        case "closed" where mergedAt != nil:
            return .merged
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
        case user
        case head
        case base
    }

    struct User: Decodable {
        var login: String
        var avatarURL: URL?

        var author: PullRequestAuthor {
            PullRequestAuthor(username: login, avatarURL: avatarURL)
        }

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

private struct GitHubPullRequestDetailPayload: Decodable {
    var pullRequest: GitHubPullRequestResponse
    var body: String?
    var assignees: [GitHubPullRequestResponse.User]

    var summary: PullRequestSummary {
        pullRequest.summary
    }

    var changesURL: URL {
        pullRequest.htmlURL.appendingPathComponent("files")
    }

    init(from decoder: Decoder) throws {
        pullRequest = try GitHubPullRequestResponse(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        assignees = try container.decodeIfPresent([GitHubPullRequestResponse.User].self, forKey: .assignees) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case body
        case assignees
    }
}

private struct GitHubIssueCommentResponse: Decodable {
    var id: Int
    var body: String
    var htmlURL: URL
    var createdAt: Date
    var updatedAt: Date
    var user: GitHubPullRequestResponse.User

    var comment: PullRequestComment {
        PullRequestComment(
            id: id,
            author: user.author,
            body: body,
            webURL: htmlURL,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case body
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case user
    }
}

private struct GitHubPullRequestReviewResponse: Decodable {
    var id: Int
    var body: String?
    var htmlURL: URL
    var submittedAt: Date?
    var user: GitHubPullRequestResponse.User

    var comment: PullRequestComment? {
        guard let submittedAt,
              let body = body?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else {
            return nil
        }
        return PullRequestComment(
            id: id,
            author: user.author,
            body: body,
            webURL: htmlURL,
            createdAt: submittedAt,
            updatedAt: submittedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case body
        case htmlURL = "html_url"
        case submittedAt = "submitted_at"
        case user
    }
}

private struct GitHubReviewCommentResponse: Decodable {
    var id: Int
    var body: String
    var htmlURL: URL
    var createdAt: Date
    var updatedAt: Date
    var user: GitHubPullRequestResponse.User

    var comment: PullRequestComment {
        PullRequestComment(
            id: id,
            author: user.author,
            body: body,
            webURL: htmlURL,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case body
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case user
    }
}

private struct GitHubErrorResponse: Decodable {
    var message: String
}

private struct GitHubCombinedStatusResponse: Decodable {
    var state: String
    var totalCount: Int

    private enum CodingKeys: String, CodingKey {
        case state
        case totalCount = "total_count"
    }
}

private struct GitHubPullRequestDetailResponse: Decodable {
    var mergeable: Bool?
}

private struct GitHubCheckRunsResponse: Decodable {
    var totalCount: Int
    var checkRuns: [CheckRun]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case checkRuns = "check_runs"
    }

    struct CheckRun: Decodable {
        var status: String
        var conclusion: String?
    }
}

private extension PullRequestCheckState {
    init(githubStatus: String) {
        switch githubStatus {
        case "success":
            self = .success
        case "pending":
            self = .pending
        case "failure":
            self = .failure
        case "error":
            self = .error
        default:
            self = .unknown
        }
    }
}

private extension PullRequestCheckState {
    init(checkRuns: [GitHubCheckRunsResponse.CheckRun]) {
        if checkRuns.contains(where: { $0.status != "completed" }) {
            self = .pending
            return
        }
        if checkRuns.contains(where: { run in
            switch run.conclusion {
            case "failure", "cancelled", "timed_out", "action_required":
                return true
            default:
                return false
            }
        }) {
            self = .failure
            return
        }
        self = .success
    }
}
