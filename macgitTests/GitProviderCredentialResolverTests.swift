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

final class GitProviderCredentialResolverTests: XCTestCase {
    func testReturnsCredentialForMatchingProviderAccount() throws {
        let account = makeProviderAccount()
        let resolver = GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: FakeCredentialTokenVault(tokensByAccountID: [account.id: makeToken("secret")])
        )

        let credential = try resolver.credential(for: "https://github.com/octocat/Hello-World.git")

        XCTAssertEqual(credential, GitCredential(username: "octocat", token: "secret"))
    }

    func testUnsupportedRemoteReturnsNil() throws {
        let resolver = GitProviderCredentialResolver(
            accounts: [makeProviderAccount()],
            tokenVault: FakeCredentialTokenVault()
        )

        XCTAssertNil(try resolver.credential(for: "https://example.com/octocat/Hello-World.git"))
    }

    func testSSHRemoteKeepsExistingBehavior() throws {
        let resolver = GitProviderCredentialResolver(
            accounts: [makeProviderAccount()],
            tokenVault: FakeCredentialTokenVault()
        )

        XCTAssertNil(try resolver.credential(for: "git@github.com:octocat/Hello-World.git"))
    }

    func testNoProviderAccountKeepsExistingBehavior() throws {
        let resolver = GitProviderCredentialResolver(
            accounts: [],
            tokenVault: FakeCredentialTokenVault()
        )

        XCTAssertNil(try resolver.credential(for: "https://github.com/octocat/Hello-World.git"))
    }

    func testMultipleMatchingAccountsThrows() {
        let first = makeProviderAccount(id: "connection-1", username: "octocat")
        let second = makeProviderAccount(id: "connection-2", username: "monalisa")
        let resolver = GitProviderCredentialResolver(
            accounts: [first, second],
            tokenVault: FakeCredentialTokenVault()
        )

        XCTAssertThrowsError(try resolver.credential(for: "https://github.com/octocat/Hello-World.git")) { error in
            XCTAssertEqual(error as? GitProviderCredentialError, .multipleMatchingAccounts(host: "github.com"))
        }
    }

    func testMissingTokenReturnsUserFacingAuthenticationError() {
        let account = makeProviderAccount()
        let resolver = GitProviderCredentialResolver(
            accounts: [account],
            tokenVault: FakeCredentialTokenVault()
        )

        XCTAssertThrowsError(try resolver.credential(for: "https://github.com/octocat/Hello-World.git")) { error in
            XCTAssertEqual(error as? GitProviderCredentialError, .tokenUnavailable(username: "octocat"))
        }
    }

    private func makeProviderAccount(
        id: String = "connection-1",
        username: String = "octocat"
    ) -> GitProviderAccount {
        GitProviderAccount(
            id: id,
            macgitUID: "macgit-user-1",
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: id,
            username: username,
            displayName: nil,
            avatarURL: nil,
            scopes: [],
            permissions: [:],
            tokenStatus: .valid,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }

    private func makeToken(_ accessToken: String) -> GitProviderToken {
        GitProviderToken(accessToken: accessToken, refreshToken: nil, expiresAt: nil, tokenType: "bearer")
    }
}

private final class FakeCredentialTokenVault: GitProviderTokenVault {
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
        tokensByAccountID[account.id] = nil
    }
}
