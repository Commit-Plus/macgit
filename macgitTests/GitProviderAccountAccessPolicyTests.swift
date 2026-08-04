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

final class GitProviderAccountAccessPolicyTests: XCTestCase {
    private let policy = GitProviderAccountAccessPolicy()

    func testFirstAccountIsAllowedWithoutMultipleAccountAccess() {
        XCTAssertEqual(
            policy.creationDecision(
                existingAccountCount: 0,
                multipleAccountAccess: .denied(.requiresPro)
            ),
            .allowed
        )
    }

    func testAdditionalAccountRequiresPro() {
        XCTAssertEqual(
            policy.creationDecision(
                existingAccountCount: 1,
                multipleAccountAccess: .denied(.requiresPro)
            ),
            .denied(.requiresPro(freeLimit: 1))
        )
    }

    func testProAllowsAdditionalAccounts() {
        XCTAssertEqual(
            policy.creationDecision(
                existingAccountCount: 4,
                multipleAccountAccess: .allowed
            ),
            .allowed
        )
    }

    func testGlobalFeatureDisableFailsClosedAtTheFreeLimit() {
        XCTAssertEqual(
            policy.creationDecision(
                existingAccountCount: 1,
                multipleAccountAccess: .denied(.featureDisabled)
            ),
            .denied(.featureDisabled)
        )
    }
}
