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

import Foundation
import XCTest
@testable import macgit

@MainActor
final class EntitlementCacheTests: XCTestCase {
    func testCachePersistsEntitlementsPerAccount() {
        let suiteName = "EntitlementCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = UserDefaultsEntitlementCache(userDefaults: defaults)
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let cached = CachedAccountEntitlement(
            entitlement: AccountEntitlement(
                plan: .pro,
                access: .active,
                billingStatus: .active,
                source: .polar
            ),
            updatedAt: updatedAt
        )

        cache.save(cached, for: "user-a")

        XCTAssertEqual(cache.cachedEntitlement(for: "user-a"), cached)
        XCTAssertNil(cache.cachedEntitlement(for: "user-b"))

        cache.removeEntitlement(for: "user-a")
        XCTAssertNil(cache.cachedEntitlement(for: "user-a"))
    }
}
