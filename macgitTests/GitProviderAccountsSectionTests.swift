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

final class GitProviderAccountsSectionTests: XCTestCase {
    func testGuestCannotConnectProviderUntilSignedIn() {
        XCTAssertEqual(
            GitProviderAccountsPresentationPolicy.actions(isSignedIn: false, account: nil),
            []
        )
    }

    func testSignedInUserSeesAddGitHubAndAddGitLabActions() {
        XCTAssertEqual(
            GitProviderAccountsPresentationPolicy.actions(isSignedIn: true, account: nil),
            [.add]
        )
    }

    func testAddAccountHostOptionsExposeUnsupportedBitbucketAsDisabled() {
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.hostOptions,
            [
                GitProviderAddAccountOption(id: .github, title: "GitHub", isEnabled: true),
                GitProviderAddAccountOption(id: .gitlab, title: "GitLab", isEnabled: true),
                GitProviderAddAccountOption(id: .bitbucket, title: "Bitbucket", isEnabled: false)
            ]
        )
    }

    func testAddAccountAuthOptionsDisablePersonalAccessTokenUntilSupported() {
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.authTypeOptions,
            [
                GitProviderAddAccountOption(id: .oauth, title: "OAuth", isEnabled: true),
                GitProviderAddAccountOption(id: .personalAccessToken, title: "Personal Access Token", isEnabled: false)
            ]
        )
    }

    func testAddAccountProtocolOptionsDisableSSHUntilSupported() {
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.protocolOptions,
            [
                GitProviderAddAccountOption(id: .https, title: "HTTPS", isEnabled: true),
                GitProviderAddAccountOption(id: .ssh, title: "SSH", isEnabled: false)
            ]
        )
    }

    func testConnectButtonIsOnlyEnabledForSupportedOAuthHTTPSHosts() {
        XCTAssertTrue(
            GitProviderAddAccountPresentationPolicy.canConnect(
                host: .github,
                authType: .oauth,
                protocol: .https
            )
        )
        XCTAssertTrue(
            GitProviderAddAccountPresentationPolicy.canConnect(
                host: .gitlab,
                authType: .oauth,
                protocol: .https
            )
        )
        XCTAssertFalse(
            GitProviderAddAccountPresentationPolicy.canConnect(
                host: .bitbucket,
                authType: .oauth,
                protocol: .https
            )
        )
        XCTAssertFalse(
            GitProviderAddAccountPresentationPolicy.canConnect(
                host: .github,
                authType: .personalAccessToken,
                protocol: .https
            )
        )
        XCTAssertFalse(
            GitProviderAddAccountPresentationPolicy.canConnect(
                host: .github,
                authType: .oauth,
                protocol: .ssh
            )
        )
    }

    func testAddAccountUsernamePlaceholderIsEmptyUntilConnectionCompletes() {
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.usernameDisplayText(for: ""),
            "_"
        )
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.usernameDisplayText(for: "Tranthanh98"),
            "Tranthanh98"
        )
    }

    func testAddAccountConnectButtonTitleReflectsConnectionState() {
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.connectButtonTitle(connectedUsername: ""),
            "Connect Account"
        )
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.connectButtonTitle(connectedUsername: "Tranthanh98"),
            "Reconnect"
        )
    }

    func testSelfHostedGitLabRequiresHostURL() throws {
        XCTAssertNil(GitProviderAccountsPresentationPolicy.normalizedSelfHostedGitLabHost(from: ""))
        XCTAssertNil(GitProviderAccountsPresentationPolicy.normalizedSelfHostedGitLabHost(from: "not a host"))

        let host = try XCTUnwrap(
            GitProviderAccountsPresentationPolicy.normalizedSelfHostedGitLabHost(from: "gitlab.example.com/gitlab")
        )

        XCTAssertEqual(host.kind, .gitlab)
        XCTAssertEqual(host.baseURL.absoluteString, "https://gitlab.example.com")
    }

    func testGitLabAccountUsesSameDisconnectFlowAsGitHub() {
        XCTAssertEqual(
            GitProviderAccountsPresentationPolicy.actions(
                isSignedIn: true,
                account: makeAccount(provider: .gitlab, tokenStatus: .valid)
            ),
            [.edit, .delete]
        )
    }

    func testUnavailableOnDeviceShowsEditAndDeleteActions() {
        XCTAssertEqual(
            GitProviderAccountsPresentationPolicy.actions(
                isSignedIn: true,
                account: makeAccount(provider: .github, tokenStatus: .unavailableOnThisDevice)
            ),
            [.edit, .delete]
        )
    }

    func testValidAccountShowsEditAndDeleteActions() {
        XCTAssertEqual(
            GitProviderAccountsPresentationPolicy.actions(
                isSignedIn: true,
                account: makeAccount(provider: .github, tokenStatus: .valid)
            ),
            [.edit, .delete]
        )
    }

    func testEditAccountPrefillHostComesFromProvider() {
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.host(for: makeAccount(provider: .github, tokenStatus: .valid)),
            .github
        )
        XCTAssertEqual(
            GitProviderAddAccountPresentationPolicy.host(for: makeAccount(provider: .gitlab, tokenStatus: .valid)),
            .gitlab
        )
    }

    private func makeAccount(
        provider: GitProviderKind,
        tokenStatus: GitProviderTokenStatus
    ) -> GitProviderAccount {
        GitProviderAccount(
            id: "connection-1",
            macgitUID: "macgit-user-1",
            provider: provider,
            hostURL: provider == .github
                ? URL(string: "https://github.com")!
                : URL(string: "https://gitlab.com")!,
            providerUserID: "583231",
            username: "octocat",
            displayName: "The Octocat",
            avatarURL: nil,
            scopes: ["repo"],
            permissions: [:],
            tokenStatus: tokenStatus,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }
}
