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
final class PullRequestControllerTests: XCTestCase {
    func testLoadPullRequestsRequiresConnectedProviderAccount() async throws {
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: []),
            tokenVault: FakePullRequestTokenVault()
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(),
            services: [.github: FakePullRequestProvider()]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")

        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertEqual(controller.errorMessage, "Connect Account...")
    }

    func testLoadPullRequestsPublishesResults() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")

        XCTAssertEqual(controller.items, [makeSummary()])
        XCTAssertNil(controller.errorMessage)
        XCTAssertEqual(controller.selectedProviderAccountID, account.id)
        XCTAssertEqual(service.receivedRepository?.owner, "octocat")
        XCTAssertEqual(service.receivedRepository?.name, "Hello-World")
        XCTAssertEqual(service.receivedToken, token)
        XCTAssertEqual(service.receivedFilter, .open)
        XCTAssertEqual(service.receivedPage, 1)
        XCTAssertEqual(service.receivedPerPage, 30)
    }

    func testLoadPullRequestsPublishesPermissionError() async throws {
        let account = makeAccount()
        let token = makeToken()
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: FakePullRequestProvider(result: .failure(.permissionDenied))]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")

        XCTAssertTrue(controller.items.isEmpty)
        XCTAssertEqual(
            controller.errorMessage,
            PullRequestProviderError.permissionDenied.localizedDescription
        )
    }

    func testOpenInBrowserUsesPullRequestWebURL() throws {
        var openedURL: URL?
        let controller = PullRequestController(
            providerAccountController: GitProviderAccountController(
                store: FakePullRequestAccountStore(accounts: []),
                tokenVault: FakePullRequestTokenVault()
            ),
            tokenVault: FakePullRequestTokenVault(),
            services: [:],
            openURL: { url in
                openedURL = url
                return true
            }
        )

        controller.openInBrowser(makeSummary())

        XCTAssertEqual(openedURL?.absoluteString, "https://github.com/octocat/Hello-World/pull/12")
    }

    func testVisibleItemsApplyStateAndCreatedByMeFilters() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([
            makeSummary(number: 12, state: .open, author: "octocat"),
            makeSummary(number: 13, state: .merged, author: "teammate"),
            makeSummary(number: 14, state: .closed, author: "octocat"),
        ]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        controller.stateFilter = .closed
        controller.createdByMeOnly = true

        XCTAssertEqual(controller.visibleItems.map(\.number), [14])
    }

    func testLoadNextPageRequestsNextProviderPage() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(
            result: .success([makeSummary(number: 12)]),
            hasNextPage: true
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-pagination")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        await controller.loadNextPage(repositoryURL: repositoryURL)

        XCTAssertEqual(service.receivedPage, 2)
        XCTAssertEqual(controller.currentPage, 2)
        XCTAssertTrue(controller.hasNextPage)
    }

    func testLoadPullRequestDetailPublishesSelectedDetail() async throws {
        let account = makeAccount()
        let token = makeToken()
        let detail = PullRequestDetail(
            summary: makeSummary(),
            body: "Adds pull request detail.",
            assignees: [PullRequestAuthor(username: "teammate", avatarURL: nil)],
            comments: [],
            changesURL: URL(string: "https://github.com/octocat/Hello-World/pull/12/files")!
        )
        let service = FakePullRequestProvider(
            result: .success([makeSummary()]),
            detailResult: .success(detail)
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.loadPullRequestDetail(makeSummary())

        XCTAssertEqual(controller.selectedDetail, detail)
        XCTAssertEqual(service.receivedDetailNumber, 12)
    }

    func testOpenChangesInBrowserUsesDetailChangesURL() {
        var openedURL: URL?
        let controller = PullRequestController(
            providerAccountController: GitProviderAccountController(
                store: FakePullRequestAccountStore(accounts: []),
                tokenVault: FakePullRequestTokenVault()
            ),
            tokenVault: FakePullRequestTokenVault(),
            services: [:],
            openURL: { url in
                openedURL = url
                return true
            }
        )
        let detail = PullRequestDetail(
            summary: makeSummary(),
            body: "",
            assignees: [],
            comments: [],
            changesURL: URL(string: "https://github.com/octocat/Hello-World/pull/12/files")!
        )

        controller.openChangesInBrowser(detail)

        XCTAssertEqual(openedURL?.absoluteString, "https://github.com/octocat/Hello-World/pull/12/files")
    }

    func testPresentCreatePullRequestUsesCurrentBranchAndSuggestedTitle() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-actions")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "feature/pr-actions" },
            localBranchesProvider: { _ in ["main", "feature/pr-actions"] }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        await controller.presentCreatePullRequest()

        XCTAssertEqual(controller.createDraftSeed?.sourceBranch, "feature/pr-actions")
        XCTAssertEqual(controller.createDraftSeed?.targetBranch, "main")
        XCTAssertEqual(controller.createDraftSeed?.suggestedTitle, "Pr Actions")
    }

    func testCreatePullRequestRequiresValidDraft() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        let invalidDraft = try PullRequestDraft(
            repository: GitRepositoryIdentity(
                provider: .github,
                hostURL: URL(string: "https://github.com")!,
                owner: "octocat",
                name: "Hello-World"
            ),
            sourceBranch: "feature",
            targetBranch: "main",
            title: "Valid title",
            body: ""
        )
        var mutatedDraft = invalidDraft
        mutatedDraft.title = " "

        await controller.createPullRequest(mutatedDraft)

        XCTAssertEqual(controller.detailErrorMessage, "Pull request title is required.")
        XCTAssertNil(service.createdDraft)
    }

    func testCreatePullRequestRefreshesListAfterSuccess() async throws {
        let account = makeAccount()
        let token = makeToken()
        let createdSummary = makeSummary(number: 30)
        let service = FakePullRequestProvider(
            result: .success([createdSummary]),
            createResult: .success(createdSummary)
        )
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-create")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "feature/pr-actions" },
            localBranchesProvider: { _ in ["main", "feature/pr-actions"] }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        let draft = try PullRequestDraft(
            repository: GitRepositoryIdentity(
                provider: .github,
                hostURL: URL(string: "https://github.com")!,
                owner: "octocat",
                name: "Hello-World"
            ),
            sourceBranch: "feature/pr-actions",
            targetBranch: "main",
            title: "Add provider-backed pull request actions",
            body: ""
        )

        await controller.createPullRequest(draft)

        XCTAssertEqual(service.createdDraft, draft)
        XCTAssertEqual(controller.items, [createdSummary])
    }

    func testCommentRequiresNonEmptyBody() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary()]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service]
        )

        await controller.loadPullRequests(remoteURLString: "https://github.com/octocat/Hello-World.git")
        await controller.comment(on: makeSummary(), body: "   ")

        XCTAssertEqual(controller.detailErrorMessage, "Pull request comment is required.")
        XCTAssertNil(service.createdCommentBody)
    }

    func testCheckoutPRFetchesProviderRefWhenNeeded() async throws {
        let account = makeAccount()
        let token = makeToken()
        let service = FakePullRequestProvider(result: .success([makeSummary(number: 18)]))
        let accountController = GitProviderAccountController(
            store: FakePullRequestAccountStore(accounts: [account]),
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token])
        )
        await accountController.updateMacgitAccount(AccountSnapshot(
            uid: "macgit-user-1",
            email: "user@example.com",
            displayName: nil,
            providerIDs: []
        ))

        var fetchedReference: (remote: String, reference: String, localBranch: String)?
        var checkedOutBranch: String?
        let repositoryURL = URL(fileURLWithPath: "/tmp/macgit-pr-checkout")
        let controller = PullRequestController(
            providerAccountController: accountController,
            tokenVault: FakePullRequestTokenVault(tokensByAccountID: [account.id: token]),
            services: [.github: service],
            remoteNameProvider: { _ in "origin" },
            remoteURLProvider: { _, _ in "https://github.com/octocat/Hello-World.git" },
            currentBranchProvider: { _ in "main" },
            localBranchesProvider: { _ in ["main"] },
            fetchPullRequestRef: { remote, reference, localBranch, _, _ in
                fetchedReference = (remote, reference, localBranch)
            },
            checkoutBranch: { branch, _ in
                checkedOutBranch = branch
            }
        )

        await controller.loadPullRequests(repositoryURL: repositoryURL)
        await controller.checkout(makeSummary(number: 18))

        XCTAssertEqual(fetchedReference?.remote, "origin")
        XCTAssertEqual(fetchedReference?.reference, "pull/18/head")
        XCTAssertEqual(fetchedReference?.localBranch, "pr/18")
        XCTAssertEqual(checkedOutBranch, "pr/18")
    }

    private func makeAccount() -> GitProviderAccount {
        GitProviderAccount(
            id: "macgit-user-1:github:github.com:583231",
            macgitUID: "macgit-user-1",
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: "583231",
            username: "octocat",
            displayName: "The Octocat",
            avatarURL: nil,
            scopes: ["repo", "read:user"],
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_000)
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

    private func makeSummary(
        number: Int = 12,
        state: PullRequestState = .open,
        author: String = "octocat"
    ) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Add provider-backed pull request read",
            state: state,
            author: PullRequestAuthor(username: author, avatarURL: nil),
            source: PullRequestBranchRef(label: "octocat:feature", ref: "feature", sha: "abc123"),
            target: PullRequestBranchRef(label: "octocat:main", ref: "main", sha: "def456"),
            webURL: URL(string: "https://github.com/octocat/Hello-World/pull/\(number)")!,
            createdAt: Date(timeIntervalSince1970: 1_779_900_000),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }
}

@MainActor
private final class FakePullRequestAccountStore: GitProviderAccountStore {
    private var accounts: [GitProviderAccount]

    init(accounts: [GitProviderAccount]) {
        self.accounts = accounts
    }

    func accounts(forMacgitUID uid: String) async throws -> [GitProviderAccount] {
        accounts.filter { $0.macgitUID == uid }
    }

    func save(_ account: GitProviderAccount) async throws {
        accounts.append(account)
    }

    func delete(accountID: String, macgitUID: String) async throws {
        accounts.removeAll { $0.id == accountID && $0.macgitUID == macgitUID }
    }
}

private final class FakePullRequestTokenVault: GitProviderTokenVault {
    private var tokensByAccountID: [String: GitProviderToken]

    init(tokensByAccountID: [String: GitProviderToken] = [:]) {
        self.tokensByAccountID = tokensByAccountID
    }

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        tokensByAccountID[account.id]
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {
        tokensByAccountID[account.id] = token
    }

    func deleteToken(for account: GitProviderAccount) throws {
        tokensByAccountID.removeValue(forKey: account.id)
    }
}

private final class FakePullRequestProvider: PullRequestProviding {
    private let result: Result<[PullRequestSummary], PullRequestProviderError>
    private let detailResult: Result<PullRequestDetail, PullRequestProviderError>
    private let createResult: Result<PullRequestSummary, PullRequestProviderError>
    private let commentResult: Result<Void, PullRequestProviderError>
    private let hasPreviousPage: Bool
    private let hasNextPage: Bool
    private(set) var receivedRepository: GitRepositoryIdentity?
    private(set) var receivedToken: GitProviderToken?
    private(set) var receivedFilter: PullRequestListFilter?
    private(set) var receivedPage: Int?
    private(set) var receivedPerPage: Int?
    private(set) var receivedDetailNumber: Int?
    private(set) var createdDraft: PullRequestDraft?
    private(set) var createdCommentBody: String?

    init(
        result: Result<[PullRequestSummary], PullRequestProviderError> = .success([]),
        detailResult: Result<PullRequestDetail, PullRequestProviderError> = .failure(.providerMessage("No detail")),
        createResult: Result<PullRequestSummary, PullRequestProviderError> = .failure(.providerMessage("No create")),
        commentResult: Result<Void, PullRequestProviderError> = .success(()),
        hasPreviousPage: Bool = false,
        hasNextPage: Bool = false
    ) {
        self.result = result
        self.detailResult = detailResult
        self.createResult = createResult
        self.commentResult = commentResult
        self.hasPreviousPage = hasPreviousPage
        self.hasNextPage = hasNextPage
    }

    func listPullRequests(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        filter: PullRequestListFilter,
        page: Int,
        perPage: Int
    ) async throws -> PullRequestListPage {
        receivedRepository = repository
        receivedToken = token
        receivedFilter = filter
        receivedPage = page
        receivedPerPage = perPage
        return PullRequestListPage(
            items: try result.get(),
            page: page,
            perPage: perPage,
            hasPreviousPage: hasPreviousPage,
            hasNextPage: hasNextPage
        )
    }

    func pullRequestDetail(
        repository: GitRepositoryIdentity,
        token: GitProviderToken,
        number: Int
    ) async throws -> PullRequestDetail {
        receivedRepository = repository
        receivedToken = token
        receivedDetailNumber = number
        return try detailResult.get()
    }

    func createPullRequest(
        _ draft: PullRequestDraft,
        token: GitProviderToken
    ) async throws -> PullRequestSummary {
        createdDraft = draft
        receivedToken = token
        return try createResult.get()
    }

    func createComment(
        body: String,
        on pullRequest: PullRequestSummary,
        repository: GitRepositoryIdentity,
        token: GitProviderToken
    ) async throws {
        createdCommentBody = body
        receivedRepository = repository
        receivedToken = token
        _ = pullRequest
        _ = try commentResult.get()
    }
}
