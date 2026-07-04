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
final class AccountSessionControllerTests: XCTestCase {
    func testGuestRemainsAvailableWhenFirebaseIsMissing() {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(current: nil),
            bootstrapStatus: .missingConfiguration
        )

        XCTAssertEqual(controller.state, .guest)
        XCTAssertFalse(controller.cloudFeaturesAvailable)
    }

    func testEmailSignInPublishesAccount() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let controller = AccountSessionController(
            auth: FakeAccountAuth(signInResult: account),
            bootstrapStatus: .configured
        )

        await controller.signIn(email: "a@example.com", password: "secret12")

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertNil(controller.errorMessage)
    }

    func testSignInFailureReturnsToGuestAndPublishesMessage() async {
        let controller = AccountSessionController(
            auth: FakeAccountAuth(error: .invalidCredentials),
            bootstrapStatus: .configured
        )

        await controller.signIn(email: "a@example.com", password: "wrong")

        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(controller.errorMessage, "The email or password is incorrect.")
    }

    func testSignOutReturnsToGuest() {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        controller.signOut()

        XCTAssertEqual(controller.state, .guest)
        XCTAssertEqual(auth.signOutCallCount, 1)
    }

    func testSuccessfulAccountDeletionReturnsToGuest() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(auth.deleteAccountCallCount, 1)
        XCTAssertEqual(controller.state, .guest)
    }

    func testFailedAccountDeletionKeepsAuthenticatedState() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account, error: .networkUnavailable)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertEqual(controller.errorMessage, "Connect to the internet and try again.")
    }

    func testRecentAuthenticationFailureKeepsAccountAndOffersRecovery() async {
        let account = AccountSnapshot(
            uid: "u1",
            email: "a@example.com",
            displayName: nil,
            providerIDs: ["password"]
        )
        let auth = FakeAccountAuth(current: account, error: .requiresRecentAuthentication)
        let controller = AccountSessionController(auth: auth, bootstrapStatus: .configured)

        await controller.deleteAccount()

        XCTAssertEqual(controller.state, .authenticated(account))
        XCTAssertTrue(controller.requiresRecentAuthentication)
    }
}

private final class FakeAccountAuth: AccountAuthenticating {
    var currentAccount: AccountSnapshot?
    var signOutCallCount = 0
    var deleteAccountCallCount = 0

    private let signInResult: AccountSnapshot?
    private let error: AccountAuthError?

    init(
        current: AccountSnapshot? = nil,
        signInResult: AccountSnapshot? = nil,
        error: AccountAuthError? = nil
    ) {
        currentAccount = current
        self.signInResult = signInResult
        self.error = error
    }

    func signIn(email: String, password: String) async throws -> AccountSnapshot {
        if let error { throw error }
        return try XCTUnwrap(signInResult)
    }

    func createAccount(email: String, password: String) async throws -> AccountSnapshot {
        try await signIn(email: email, password: password)
    }

    func signInWithGoogle() async throws -> AccountSnapshot {
        try await signIn(email: "", password: "")
    }

    func completePendingLink(email: String, password: String) async throws -> AccountSnapshot {
        try await signIn(email: email, password: password)
    }

    func sendPasswordReset(email: String) async throws {
        if let error { throw error }
    }

    func deleteAccount() async throws {
        if let error { throw error }
        deleteAccountCallCount += 1
        currentAccount = nil
    }

    func signOut() throws {
        if let error { throw error }
        signOutCallCount += 1
        currentAccount = nil
    }
}
