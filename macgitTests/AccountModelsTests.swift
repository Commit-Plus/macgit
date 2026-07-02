//
//  AccountModelsTests.swift
//  macgitTests
//

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

final class AccountModelsTests: XCTestCase {
    func testMissingEntitlementNormalizesToFree() {
        XCTAssertEqual(AccountEntitlement.free.plan, .free)
        XCTAssertFalse(AccountEntitlement.free.hasProAccess)
    }

    func testOnlyActiveProGrantsAccess() {
        XCTAssertTrue(
            AccountEntitlement(
                plan: .pro,
                access: .active,
                billingStatus: .active
            ).hasProAccess
        )
        XCTAssertFalse(
            AccountEntitlement(
                plan: .pro,
                access: .inactive,
                billingStatus: .pastDue
            ).hasProAccess
        )
    }

    func testAccountSnapshotUsesEmailFallback() {
        let snapshot = AccountSnapshot(
            uid: "uid-1",
            email: nil,
            displayName: nil,
            providerIDs: ["password"]
        )

        XCTAssertEqual(snapshot.displayLabel, "Commit+ Account")
    }
}
