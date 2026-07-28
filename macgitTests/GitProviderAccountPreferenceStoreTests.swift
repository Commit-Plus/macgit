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

final class GitProviderAccountPreferenceStoreTests: XCTestCase {
    func testPersistsAccountPreferenceForCanonicalRemoteIdentity() throws {
        let defaultsKey = "test.provider-account-preferences.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: defaultsKey)
        defer { defaults.removeObject(forKey: defaultsKey) }

        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "git@github.com:octocat/Hello-World.git"
        ))
        let store = GitProviderAccountPreferenceStore(userDefaults: defaults, key: defaultsKey)

        store.update(accountID: "connection-work", for: identity)

        let reloadedStore = GitProviderAccountPreferenceStore(userDefaults: defaults, key: defaultsKey)
        XCTAssertEqual(reloadedStore.accountID(for: identity), "connection-work")
    }

    func testRemovingPreferencePersistsAutomaticSelection() throws {
        let defaultsKey = "test.provider-account-preferences.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: defaultsKey)
        defer { defaults.removeObject(forKey: defaultsKey) }

        let identity = try XCTUnwrap(GitRemoteIdentityResolver.identity(
            from: "https://gitlab.com/group/project.git"
        ))
        let store = GitProviderAccountPreferenceStore(userDefaults: defaults, key: defaultsKey)
        store.update(accountID: "connection-work", for: identity)

        store.update(accountID: nil, for: identity)

        XCTAssertNil(store.accountID(for: identity))
        XCTAssertTrue(store.preferences.isEmpty)
    }
}
