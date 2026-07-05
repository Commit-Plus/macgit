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
final class EntitlementGateTests: XCTestCase {
    private let account = AccountSnapshot(
        uid: "u1",
        email: "a@example.com",
        displayName: nil,
        providerIDs: ["password"]
    )

    func testExistingSessionStartsExactlyOneObservation() {
        let provider = FakeEntitlementProvider()
        _ = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )

        XCTAssertEqual(provider.observedUIDs, ["u1"])
    }

    func testSignInStartsObservationAndProUpdateChangesMenuPolicy() async {
        let provider = FakeEntitlementProvider()
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(signInResult: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )

        await controller.signIn(email: "a@example.com", password: "secret12")
        provider.send(.pro)

        XCTAssertEqual(provider.observedUIDs, ["u1"])
        XCTAssertTrue(controller.entitlement.hasProAccess)
        XCTAssertEqual(
            AccountMenuPolicy.actions(account: controller.account, entitlement: controller.entitlement),
            [.manageAccount, .syncStatus, .manageSubscriptionComingLater, .signOut]
        )
    }

    func testSignOutCancelsObservationAndResetsFree() {
        let provider = FakeEntitlementProvider()
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )
        provider.send(.pro)

        controller.signOut()

        XCTAssertEqual(provider.token.cancelCount, 1)
        XCTAssertEqual(controller.entitlement, .free)

        provider.send(.pro)
        XCTAssertEqual(controller.entitlement, .free)
    }

    func testListenerFailureNeverGrantsAccess() {
        let provider = FakeEntitlementProvider()
        let controller = AccountSessionController(
            auth: EntitlementFakeAuth(current: account),
            bootstrapStatus: .configured,
            entitlementProvider: provider
        )
        provider.send(.pro)

        provider.fail("Firestore unavailable")

        XCTAssertEqual(controller.entitlement, .free)
        XCTAssertEqual(controller.entitlementError, "Firestore unavailable")
    }
}

private extension AccountEntitlement {
    static let pro = AccountEntitlement(
        plan: .pro,
        access: .active,
        billingStatus: .active,
        source: .adminTest
    )
}

@MainActor
private final class FakeEntitlementProvider: EntitlementProviding {
    let token = FakeObservationToken()
    var observedUIDs: [String] = []
    private var onChange: ((AccountEntitlement) -> Void)?
    private var onError: ((String) -> Void)?

    func observe(
        uid: String,
        onChange: @escaping (AccountEntitlement) -> Void,
        onError: @escaping (String) -> Void
    ) -> ObservationToken {
        observedUIDs.append(uid)
        self.onChange = onChange
        self.onError = onError
        return token
    }

    func send(_ entitlement: AccountEntitlement) {
        onChange?(entitlement)
    }

    func fail(_ message: String) {
        onError?(message)
    }
}

private final class FakeObservationToken: ObservationToken {
    private(set) var cancelCount = 0
    func cancel() { cancelCount += 1 }
}

private final class EntitlementFakeAuth: AccountAuthenticating {
    var currentAccount: AccountSnapshot?
    private let signInResult: AccountSnapshot?

    init(current: AccountSnapshot? = nil, signInResult: AccountSnapshot? = nil) {
        currentAccount = current
        self.signInResult = signInResult
    }

    func signIn(email: String, password: String) async throws -> AccountSnapshot {
        guard let signInResult else { throw AccountAuthError.invalidCredentials }
        currentAccount = signInResult
        return signInResult
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

    func sendPasswordReset(email: String) async throws {}
    func deleteAccount() async throws { currentAccount = nil }

    func signOut() throws {
        currentAccount = nil
    }
}
