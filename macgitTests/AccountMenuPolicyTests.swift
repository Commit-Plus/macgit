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

final class AccountMenuPolicyTests: XCTestCase {
    private let account = AccountSnapshot(
        uid: "u1",
        email: "a@example.com",
        displayName: nil,
        providerIDs: ["password"]
    )

    func testGuestActionsUseApprovedOrder() {
        XCTAssertEqual(
            AccountMenuPolicy.actions(account: nil, entitlement: .free),
            [.signIn, .createAccount, .syncLocked, .upgrade]
        )
    }

    func testFreeActionsUseApprovedOrder() {
        XCTAssertEqual(
            AccountMenuPolicy.actions(account: account, entitlement: .free),
            [.manageAccount, .syncLocked, .upgrade, .signOut]
        )
    }

    func testProActionsUseApprovedOrder() {
        let entitlement = AccountEntitlement(
            plan: .pro,
            access: .active,
            billingStatus: .active
        )

        XCTAssertEqual(
            AccountMenuPolicy.actions(account: account, entitlement: entitlement),
            [.manageAccount, .syncStatus, .manageSubscriptionComingLater, .signOut]
        )
    }

    func testPausedProKeepsSyncStatusVisible() {
        let entitlement = AccountEntitlement(
            plan: .pro,
            access: .inactive,
            billingStatus: .pastDue
        )

        XCTAssertEqual(
            AccountMenuPolicy.actions(account: account, entitlement: entitlement),
            [.manageAccount, .syncStatus, .manageSubscriptionComingLater, .signOut]
        )
    }
}
