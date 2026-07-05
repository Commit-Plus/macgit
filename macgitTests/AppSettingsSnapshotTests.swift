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

final class AppSettingsSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsOnlyApprovedSettings() throws {
        let value = AppSettingsSnapshot(
            showToolbarButtonText: false,
            showSubmodules: true,
            showSubtrees: true
        )

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(
            Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys),
            ["schemaVersion", "showToolbarButtonText", "showSubmodules", "showSubtrees"]
        )
    }

    func testAppStateApplyChangesOnlyApprovedSettings() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)
        state.hasOpenRepository = true
        state.newWindowRepoURL = URL(fileURLWithPath: "/tmp/repository")

        state.apply(
            AppSettingsSnapshot(
                showToolbarButtonText: false,
                showSubmodules: true,
                showSubtrees: true
            )
        )

        XCTAssertEqual(
            state.snapshot,
            AppSettingsSnapshot(
                showToolbarButtonText: false,
                showSubmodules: true,
                showSubtrees: true
            )
        )
        XCTAssertTrue(state.hasOpenRepository)
        XCTAssertEqual(state.newWindowRepoURL, URL(fileURLWithPath: "/tmp/repository"))
    }

    func testSyncEnabledIsDeviceLocalAndPersisted() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertFalse(state.syncEnabled)

        state.syncEnabled = true

        XCTAssertTrue(AppState(userDefaults: defaults).syncEnabled)
        XCTAssertEqual(defaults.object(forKey: "settingsSyncEnabled") as? Bool, true)
    }
}
