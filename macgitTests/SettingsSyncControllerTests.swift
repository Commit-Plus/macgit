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
final class SettingsSyncControllerTests: XCTestCase {
    private let account = AccountSnapshot(
        uid: "u1",
        email: "a@example.com",
        displayName: nil,
        providerIDs: ["password"]
    )
    private let cloud = AppSettingsSnapshot(
        showToolbarButtonText: false,
        showSubmodules: true,
        showSubtrees: true
    )

    func testProConflictPresentsSingleInitialChoiceSheet() async {
        let harness = makeHarness(cloud: cloud, enabled: true)
        harness.entitlements.send(.activePro)

        await harness.controller.synchronizeSettingsNow()

        XCTAssertEqual(harness.controller.settingsSyncStatus, .needsInitialChoice(cloud))
        XCTAssertEqual(harness.controller.presentedSheet, .settingsConflict)
        XCTAssertEqual(harness.controller.pendingCloudSettings, cloud)
    }

    func testPastDuePreservesEnabledPreferenceAndPauses() async {
        let harness = makeHarness(cloud: cloud, enabled: true)
        harness.entitlements.send(.pastDuePro)

        await harness.controller.synchronizeSettingsNow()

        XCTAssertTrue(harness.controller.settingsSyncEnabled)
        XCTAssertEqual(harness.controller.settingsSyncStatus, .paused)
    }

    func testCancelInitialChoiceTurnsDeviceSyncOff() async {
        let harness = makeHarness(cloud: cloud, enabled: true)
        harness.entitlements.send(.activePro)
        await harness.controller.synchronizeSettingsNow()

        await harness.controller.resolveInitialSettingsChoice(.cancel)

        XCTAssertFalse(harness.controller.settingsSyncEnabled)
        XCTAssertEqual(harness.controller.settingsSyncStatus, .off)
        XCTAssertNil(harness.controller.presentedSheet)
    }

    private func makeHarness(cloud: AppSettingsSnapshot?, enabled: Bool) -> ControllerHarness {
        let suiteName = "SettingsSyncControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let appState = AppState(userDefaults: defaults)
        appState.syncEnabled = enabled
        let entitlements = ControllerFakeEntitlements()
        let store = ControllerFakeSettingsStore(cloud: cloud)
        let controller = AccountSessionController(
            auth: ControllerFakeAuth(account: account),
            bootstrapStatus: .configured,
            entitlementProvider: entitlements,
            appState: appState,
            settingsStore: store
        )
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return ControllerHarness(controller: controller, entitlements: entitlements)
    }
}

@MainActor
private struct ControllerHarness {
    let controller: AccountSessionController
    let entitlements: ControllerFakeEntitlements
}

private extension AccountEntitlement {
    static let activePro = AccountEntitlement(
        plan: .pro,
        access: .active,
        billingStatus: .active,
        source: .adminTest
    )

    static let pastDuePro = AccountEntitlement(
        plan: .pro,
        access: .inactive,
        billingStatus: .pastDue,
        source: .adminTest
    )
}

@MainActor
private final class ControllerFakeEntitlements: EntitlementProviding {
    private var onChange: ((AccountEntitlement) -> Void)?

    func observe(
        uid: String,
        onChange: @escaping (AccountEntitlement) -> Void,
        onError: @escaping (String) -> Void
    ) -> ObservationToken {
        self.onChange = onChange
        return ControllerObservationToken()
    }

    func send(_ entitlement: AccountEntitlement) {
        onChange?(entitlement)
    }
}

@MainActor
private final class ControllerFakeSettingsStore: CloudSettingsStore {
    var cloud: AppSettingsSnapshot?

    init(cloud: AppSettingsSnapshot?) {
        self.cloud = cloud
    }

    func load(uid: String) async throws -> AppSettingsSnapshot? { cloud }
    func save(_ snapshot: AppSettingsSnapshot, uid: String) async throws { cloud = snapshot }
    func observe(
        uid: String,
        onChange: @escaping (Result<AppSettingsSnapshot, Error>) -> Void
    ) -> ObservationToken {
        ControllerObservationToken()
    }
}

private final class ControllerObservationToken: ObservationToken {
    func cancel() {}
}

private final class ControllerFakeAuth: AccountAuthenticating {
    var currentAccount: AccountSnapshot?

    init(account: AccountSnapshot) {
        currentAccount = account
    }

    func signIn(email: String, password: String) async throws -> AccountSnapshot {
        currentAccount!
    }

    func createAccount(email: String, password: String) async throws -> AccountSnapshot {
        currentAccount!
    }

    func signInWithGoogle() async throws -> AccountSnapshot { currentAccount! }
    func completePendingLink(email: String, password: String) async throws -> AccountSnapshot { currentAccount! }
    func sendPasswordReset(email: String) async throws {}
    func deleteAccount() async throws { currentAccount = nil }
    func signOut() throws { currentAccount = nil }
}
