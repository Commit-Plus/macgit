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
final class GitProviderAccountControllerTests: XCTestCase {
    func testSignedOutStateDoesNotLoadProviderAccounts() async {
        let store = FakeGitProviderAccountStore()
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: FakeGitProviderTokenVault()
        )

        await controller.updateMacgitAccount(nil)

        XCTAssertEqual(store.loadedUIDs, [])
        XCTAssertEqual(controller.accounts, [])
    }

    func testSignedInStateLoadsAccountsForCurrentMacgitUID() async {
        let account = makeProviderAccount(macgitUID: "macgit-user-1")
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let vault = FakeGitProviderTokenVault(tokensByAccountID: [
            account.id: GitProviderToken(
                accessToken: "token",
                refreshToken: nil,
                expiresAt: nil,
                tokenType: "bearer"
            )
        ])
        let controller = GitProviderAccountController(store: store, tokenVault: vault)

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        XCTAssertEqual(store.loadedUIDs, ["macgit-user-1"])
        XCTAssertEqual(controller.accounts, [account])
    }

    func testAccountWithoutLocalTokenIsMarkedUnavailableOnThisDevice() async {
        let account = makeProviderAccount(macgitUID: "macgit-user-1", tokenStatus: .valid)
        let store = FakeGitProviderAccountStore(accountsByUID: ["macgit-user-1": [account]])
        let controller = GitProviderAccountController(
            store: store,
            tokenVault: FakeGitProviderTokenVault()
        )

        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))

        XCTAssertEqual(controller.accounts.first?.tokenStatus, .unavailableOnThisDevice)
    }

    func testDisconnectDeletesLocalTokenBeforeMetadata() async {
        let events = EventRecorder()
        let account = makeProviderAccount(macgitUID: "macgit-user-1")
        let store = FakeGitProviderAccountStore(
            accountsByUID: ["macgit-user-1": [account]],
            events: events
        )
        let vault = FakeGitProviderTokenVault(events: events)
        let controller = GitProviderAccountController(store: store, tokenVault: vault)
        await controller.updateMacgitAccount(makeMacgitAccount(uid: "macgit-user-1"))
        events.values.removeAll()

        await controller.disconnect(account)

        XCTAssertEqual(events.values, ["delete-token", "delete-metadata"])
        XCTAssertEqual(controller.accounts, [])
    }

    private func makeMacgitAccount(uid: String) -> AccountSnapshot {
        AccountSnapshot(uid: uid, email: nil, displayName: nil, providerIDs: ["password"])
    }

    private func makeProviderAccount(
        macgitUID: String,
        tokenStatus: GitProviderTokenStatus = .valid
    ) -> GitProviderAccount {
        GitProviderAccount(
            id: "connection-1",
            macgitUID: macgitUID,
            provider: .github,
            hostURL: URL(string: "https://github.com")!,
            providerUserID: "provider-user-42",
            username: "octocat",
            displayName: nil,
            avatarURL: nil,
            scopes: [],
            permissions: [:],
            tokenStatus: tokenStatus,
            connectedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: nil
        )
    }
}

@MainActor
private final class FakeGitProviderAccountStore: GitProviderAccountStore {
    private(set) var loadedUIDs: [String] = []
    private var accountsByUID: [String: [GitProviderAccount]]
    private let events: EventRecorder?

    init(
        accountsByUID: [String: [GitProviderAccount]] = [:],
        events: EventRecorder? = nil
    ) {
        self.accountsByUID = accountsByUID
        self.events = events
    }

    func accounts(forMacgitUID uid: String) async throws -> [GitProviderAccount] {
        loadedUIDs.append(uid)
        return accountsByUID[uid] ?? []
    }

    func save(_ account: GitProviderAccount) async throws {
        accountsByUID[account.macgitUID, default: []].append(account)
    }

    func delete(accountID: String, macgitUID: String) async throws {
        events?.values.append("delete-metadata")
        accountsByUID[macgitUID]?.removeAll { $0.id == accountID }
    }
}

@MainActor
private final class FakeGitProviderTokenVault: GitProviderTokenVault {
    private var tokensByAccountID: [String: GitProviderToken]
    private let events: EventRecorder?

    init(
        tokensByAccountID: [String: GitProviderToken] = [:],
        events: EventRecorder? = nil
    ) {
        self.tokensByAccountID = tokensByAccountID
        self.events = events
    }

    func readToken(for account: GitProviderAccount) throws -> GitProviderToken? {
        tokensByAccountID[account.id]
    }

    func saveToken(_ token: GitProviderToken, for account: GitProviderAccount) throws {
        tokensByAccountID[account.id] = token
    }

    func deleteToken(for account: GitProviderAccount) throws {
        events?.values.append("delete-token")
        tokensByAccountID.removeValue(forKey: account.id)
    }
}

@MainActor
private final class EventRecorder {
    var values: [String] = []
}
