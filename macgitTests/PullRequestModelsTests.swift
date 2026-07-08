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

final class PullRequestModelsTests: XCTestCase {
    func testPullRequestSummaryUsesNumberAsStableID() throws {
        let summary = PullRequestSummary(
            number: 42,
            title: "Add provider-backed pull requests",
            state: .open,
            author: PullRequestAuthor(username: "octocat", avatarURL: nil),
            source: PullRequestBranchRef(label: "octocat:feature", ref: "feature", sha: "abc123"),
            target: PullRequestBranchRef(label: "octocat:main", ref: "main", sha: "def456"),
            webURL: try XCTUnwrap(URL(string: "https://github.com/octocat/Hello-World/pull/42")),
            createdAt: Date(timeIntervalSince1970: 1_779_900_000),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
        )

        XCTAssertEqual(summary.id, 42)
    }

    func testDraftRejectsSameSourceAndTargetBranch() throws {
        let repository = GitRepositoryIdentity(
            provider: .github,
            hostURL: try XCTUnwrap(URL(string: "https://github.com")),
            owner: "octocat",
            name: "Hello-World"
        )

        XCTAssertThrowsError(try PullRequestDraft(
            repository: repository,
            sourceBranch: "feature",
            targetBranch: " feature ",
            title: "Add provider-backed pull requests",
            body: ""
        )) { error in
            XCTAssertEqual(error as? PullRequestDraftValidationError, .sameSourceAndTargetBranch)
        }
    }

    func testRepositoryIdentityBuildsBrowserURLForGitHub() throws {
        let repository = GitRepositoryIdentity(
            provider: .github,
            hostURL: try XCTUnwrap(URL(string: "https://github.com")),
            owner: "octocat",
            name: "Hello-World"
        )

        XCTAssertEqual(
            repository.browserURL?.absoluteString,
            "https://github.com/octocat/Hello-World"
        )
    }

    func testClosedPullRequestFilterIncludesMergedPullRequests() {
        XCTAssertTrue(PullRequestListFilter.closed.includes(.closed))
        XCTAssertTrue(PullRequestListFilter.closed.includes(.merged))
        XCTAssertFalse(PullRequestListFilter.closed.includes(.open))
    }
}
