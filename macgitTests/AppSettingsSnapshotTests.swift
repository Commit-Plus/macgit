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
            showSubtrees: true,
            showHeaderBranchButton: false,
            showHeaderMergeButton: true,
            showHeaderStashButton: false,
            showHeaderRemoteButton: true,
            showHeaderFinderButton: false,
            showHeaderTerminalButton: true
        )

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: data)

        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(
            Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys),
            [
                "schemaVersion",
                "showToolbarButtonText",
                "showSubmodules",
                "showSubtrees",
                "showHeaderBranchButton",
                "showHeaderMergeButton",
                "showHeaderStashButton",
                "showHeaderRemoteButton",
                "showHeaderFinderButton",
                "showHeaderTerminalButton"
            ]
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
                showSubtrees: true,
                showHeaderBranchButton: true,
                showHeaderMergeButton: true,
                showHeaderStashButton: true,
                showHeaderRemoteButton: true,
                showHeaderFinderButton: true,
                showHeaderTerminalButton: true
            )
        )

        XCTAssertEqual(
            state.snapshot,
            AppSettingsSnapshot(
                showToolbarButtonText: false,
                showSubmodules: true,
                showSubtrees: true,
                showHeaderBranchButton: true,
                showHeaderMergeButton: true,
                showHeaderStashButton: true,
                showHeaderRemoteButton: true,
                showHeaderFinderButton: true,
                showHeaderTerminalButton: true
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

    func testSearchFilterIsDeviceLocalAndPersisted() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertEqual(state.searchFilter, .all)

        state.searchFilter = .commit

        XCTAssertEqual(AppState(userDefaults: defaults).searchFilter, .commit)
        XCTAssertEqual(defaults.string(forKey: "searchFilter"), SearchFilter.commit.rawValue)
    }

    func testPreferredSearchFileApplicationIsDeviceLocalAndPersisted() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertNil(state.preferredSearchFileApplicationBundleIdentifier)

        state.preferredSearchFileApplicationBundleIdentifier = "com.microsoft.VSCode"

        XCTAssertEqual(
            AppState(userDefaults: defaults).preferredSearchFileApplicationBundleIdentifier,
            "com.microsoft.VSCode"
        )

        state.preferredSearchFileApplicationBundleIdentifier = nil
        XCTAssertNil(defaults.string(forKey: "preferredSearchFileApplication"))
    }

    func testHeaderButtonVisibilityDefaultsToTrueAndPersists() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(userDefaults: defaults)
        XCTAssertTrue(state.showHeaderBranchButton)
        XCTAssertTrue(state.showHeaderMergeButton)
        XCTAssertTrue(state.showHeaderStashButton)
        XCTAssertTrue(state.showHeaderRemoteButton)
        XCTAssertTrue(state.showHeaderFinderButton)
        XCTAssertTrue(state.showHeaderTerminalButton)

        state.showHeaderBranchButton = false
        state.showHeaderMergeButton = false
        state.showHeaderStashButton = false
        state.showHeaderRemoteButton = false
        state.showHeaderFinderButton = false
        state.showHeaderTerminalButton = false

        let reloaded = AppState(userDefaults: defaults)
        XCTAssertFalse(reloaded.showHeaderBranchButton)
        XCTAssertFalse(reloaded.showHeaderMergeButton)
        XCTAssertFalse(reloaded.showHeaderStashButton)
        XCTAssertFalse(reloaded.showHeaderRemoteButton)
        XCTAssertFalse(reloaded.showHeaderFinderButton)
        XCTAssertFalse(reloaded.showHeaderTerminalButton)
    }

    func testSettingsSnapshotPublisherDoesNotEmitOnDeviceLocalSettings() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)
        var emissions: [AppSettingsSnapshot] = []
        let cancellable = state.settingsSnapshotPublisher.sink { emissions.append($0) }

        // The publisher emits the current snapshot on subscription; device-local settings should not add more.
        state.syncEnabled = true
        state.searchFilter = .commit

        XCTAssertEqual(emissions.count, 1)
        _ = cancellable
    }

    func testSettingsSnapshotPublisherEmitsUpdatedSnapshot() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)
        var emissions: [AppSettingsSnapshot] = []
        let cancellable = state.settingsSnapshotPublisher.sink { emissions.append($0) }

        state.showHeaderBranchButton = false

        XCTAssertEqual(emissions.count, 2)
        XCTAssertEqual(emissions.last?.showHeaderBranchButton, false)
        XCTAssertEqual(emissions.last?.showHeaderMergeButton, true)
        _ = cancellable
    }

    func testApplyEmitsSingleSnapshot() {
        let suiteName = "AppSettingsSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = AppState(userDefaults: defaults)
        var emissions: [AppSettingsSnapshot] = []
        let cancellable = state.settingsSnapshotPublisher.sink { emissions.append($0) }

        state.apply(
            AppSettingsSnapshot(
                showToolbarButtonText: false,
                showSubmodules: true,
                showSubtrees: true,
                showHeaderBranchButton: false,
                showHeaderMergeButton: false,
                showHeaderStashButton: false,
                showHeaderRemoteButton: false,
                showHeaderFinderButton: false,
                showHeaderTerminalButton: false
            )
        )

        XCTAssertEqual(emissions.count, 2)
        XCTAssertEqual(emissions.last?.showToolbarButtonText, false)
        XCTAssertEqual(emissions.last?.showHeaderBranchButton, false)
        _ = cancellable
    }
}
