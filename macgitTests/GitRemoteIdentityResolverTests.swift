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

final class GitRemoteIdentityResolverTests: XCTestCase {
    func testParsesHttpsGitHubRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://github.com/octocat/Hello-World.git"
        ))

        XCTAssertEqual(identity.provider, .github)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://github.com")
        XCTAssertEqual(identity.ownerPath, "octocat")
        XCTAssertEqual(identity.repositoryName, "Hello-World")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://github.com/octocat/Hello-World.git")
    }

    func testParsesSshGitHubRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "git@github.com:octocat/Hello-World.git"
        ))

        XCTAssertEqual(identity.provider, .github)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://github.com")
        XCTAssertEqual(identity.ownerPath, "octocat")
        XCTAssertEqual(identity.repositoryName, "Hello-World")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://github.com/octocat/Hello-World.git")
    }

    func testParsesGitLabSubgroupRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://gitlab.com/group/subgroup/project.git"
        ))

        XCTAssertEqual(identity.provider, .gitlab)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://gitlab.com")
        XCTAssertEqual(identity.ownerPath, "group/subgroup")
        XCTAssertEqual(identity.repositoryName, "project")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://gitlab.com/group/subgroup/project.git")
    }

    func testParsesSelfHostedGitLabRemote() throws {
        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "git@gitlab.example.com:platform/mobile/app.git"
        ))

        XCTAssertEqual(identity.provider, .gitlab)
        XCTAssertEqual(identity.hostURL.absoluteString, "https://gitlab.example.com")
        XCTAssertEqual(identity.ownerPath, "platform/mobile")
        XCTAssertEqual(identity.repositoryName, "app")
        XCTAssertEqual(identity.canonicalHTTPSURL.absoluteString, "https://gitlab.example.com/platform/mobile/app.git")
    }

    func testUnsupportedHostReturnsNil() {
        XCTAssertNil(GitRemoteIdentityResolver.identity(from: "https://example.com/octocat/Hello-World.git"))
    }

    func testRemoteWithoutRepositoryNameReturnsNil() {
        XCTAssertNil(GitRemoteIdentityResolver.identity(from: "https://github.com/octocat"))
    }
}
