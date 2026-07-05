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
final class SettingsSyncServiceTests: XCTestCase {
    private let local = AppSettingsSnapshot(
        showToolbarButtonText: true,
        showSubmodules: false,
        showSubtrees: false
    )
    private let cloud = AppSettingsSnapshot(
        showToolbarButtonText: false,
        showSubmodules: true,
        showSubtrees: true
    )

    func testGuestIsOffAndDoesNotTouchCloud() async {
        let harness = makeHarness(cloud: cloud)

        await harness.service.updateEligibility(uid: nil, entitlement: .free, enabled: true)

        XCTAssertEqual(harness.service.status, .off)
        XCTAssertTrue(harness.store.loadedUIDs.isEmpty)
    }

    func testFreeAccountIsLocked() async {
        let harness = makeHarness(cloud: cloud)

        await harness.service.updateEligibility(uid: "u1", entitlement: .free, enabled: true)

        XCTAssertEqual(harness.service.status, .locked)
        XCTAssertTrue(harness.store.loadedUIDs.isEmpty)
    }

    func testProWithDeviceSyncDisabledIsOff() async {
        let harness = makeHarness(cloud: cloud)

        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: false)

        XCTAssertEqual(harness.service.status, .off)
        XCTAssertTrue(harness.store.loadedUIDs.isEmpty)
    }

    func testFirstEnableWithNoCloudSettingsUploadsLocalAndObserves() async {
        let harness = makeHarness(cloud: nil)

        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)

        XCTAssertEqual(harness.store.saves, [.init(uid: "u1", snapshot: local)])
        XCTAssertEqual(harness.store.observedUIDs, ["u1"])
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testEqualCloudSettingsStartObservationWithoutUpload() async {
        let harness = makeHarness(cloud: local)

        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)

        XCTAssertTrue(harness.store.saves.isEmpty)
        XCTAssertEqual(harness.store.observedUIDs, ["u1"])
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testConflictingCloudSettingsRequireInitialChoice() async {
        let harness = makeHarness(cloud: cloud)

        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)

        XCTAssertEqual(harness.service.status, .needsInitialChoice(cloud))
        XCTAssertTrue(harness.store.observedUIDs.isEmpty)
    }

    func testUseCloudChoiceAppliesCloudWithoutUploadingAndStartsObservation() async {
        let harness = makeHarness(cloud: cloud)
        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)

        await harness.service.resolveInitialChoice(.useCloud)

        XCTAssertEqual(harness.local.value, cloud)
        XCTAssertTrue(harness.store.saves.isEmpty)
        XCTAssertEqual(harness.store.observedUIDs, ["u1"])
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testKeepThisMacChoiceUploadsCurrentLocalAndStartsObservation() async {
        let harness = makeHarness(cloud: cloud)
        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)

        await harness.service.resolveInitialChoice(.keepThisMac)

        XCTAssertEqual(harness.store.saves, [.init(uid: "u1", snapshot: local)])
        XCTAssertEqual(harness.store.observedUIDs, ["u1"])
        XCTAssertEqual(harness.service.status, .syncing)
    }

    func testCancelChoiceTurnsDeviceSyncOff() async {
        let harness = makeHarness(cloud: cloud)
        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)

        await harness.service.resolveInitialChoice(.cancel)

        XCTAssertEqual(harness.syncEnabled.values, [false])
        XCTAssertEqual(harness.service.status, .off)
    }

    func testRemoteApplyDoesNotEchoUpload() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)

        harness.store.send(cloud)
        harness.service.localSettingsDidChange(cloud)
        await harness.scheduler.fireAll()

        XCTAssertEqual(harness.local.value, cloud)
        XCTAssertTrue(harness.store.saves.isEmpty)
    }

    func testLocalEditsAreDebouncedAndOnlyLatestSnapshotUploads() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)
        let first = AppSettingsSnapshot(
            showToolbarButtonText: false,
            showSubmodules: false,
            showSubtrees: false
        )

        harness.service.localSettingsDidChange(first)
        harness.service.localSettingsDidChange(cloud)
        await harness.scheduler.fireAll()

        XCTAssertEqual(harness.store.saves, [.init(uid: "u1", snapshot: cloud)])
    }

    func testSignOutDisableAndPastDueCancelObservationAndPendingUpload() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)
        harness.service.localSettingsDidChange(cloud)

        await harness.service.updateEligibility(uid: nil, entitlement: .free, enabled: true)
        XCTAssertEqual(harness.store.tokens.last?.cancelCount, 1)
        XCTAssertEqual(harness.service.status, .off)

        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)
        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: false)
        XCTAssertEqual(harness.store.tokens.last?.cancelCount, 1)
        XCTAssertEqual(harness.service.status, .off)

        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)
        await harness.service.updateEligibility(uid: "u1", entitlement: .pastDuePro, enabled: true)
        XCTAssertEqual(harness.store.tokens.last?.cancelCount, 1)
        XCTAssertEqual(harness.service.status, .paused)

        await harness.scheduler.fireAll()
        XCTAssertTrue(harness.store.saves.isEmpty)
    }

    func testProRestorationResumesWhenDevicePreferenceRemainsEnabled() async {
        let harness = makeHarness(cloud: local)
        await harness.service.updateEligibility(uid: "u1", entitlement: .pastDuePro, enabled: true)
        XCTAssertEqual(harness.service.status, .paused)

        await harness.service.updateEligibility(uid: "u1", entitlement: .activePro, enabled: true)

        XCTAssertEqual(harness.store.loadedUIDs, ["u1"])
        XCTAssertEqual(harness.store.observedUIDs, ["u1"])
        XCTAssertEqual(harness.service.status, .syncing)
    }

    private func makeHarness(cloud: AppSettingsSnapshot?) -> Harness {
        let store = FakeCloudSettingsStore(cloud: cloud)
        let localBox = SnapshotBox(local)
        let syncEnabled = BoolRecorder()
        let scheduler = ManualSettingsSyncScheduler()
        let service = SettingsSyncService(
            store: store,
            currentSnapshot: { localBox.value },
            applySnapshot: { localBox.value = $0 },
            setSyncEnabled: { syncEnabled.values.append($0) },
            debounceScheduler: scheduler
        )
        return Harness(
            service: service,
            store: store,
            local: localBox,
            syncEnabled: syncEnabled,
            scheduler: scheduler
        )
    }
}

@MainActor
private struct Harness {
    let service: SettingsSyncService
    let store: FakeCloudSettingsStore
    let local: SnapshotBox
    let syncEnabled: BoolRecorder
    let scheduler: ManualSettingsSyncScheduler
}

private final class SnapshotBox {
    var value: AppSettingsSnapshot
    init(_ value: AppSettingsSnapshot) { self.value = value }
}

private final class BoolRecorder {
    var values: [Bool] = []
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
private final class FakeCloudSettingsStore: CloudSettingsStore {
    struct Save: Equatable {
        let uid: String
        let snapshot: AppSettingsSnapshot
    }

    var cloud: AppSettingsSnapshot?
    var loadedUIDs: [String] = []
    var observedUIDs: [String] = []
    var saves: [Save] = []
    var tokens: [SyncFakeObservationToken] = []
    private var onChange: ((Result<AppSettingsSnapshot, Error>) -> Void)?

    init(cloud: AppSettingsSnapshot?) {
        self.cloud = cloud
    }

    func load(uid: String) async throws -> AppSettingsSnapshot? {
        loadedUIDs.append(uid)
        return cloud
    }

    func save(_ snapshot: AppSettingsSnapshot, uid: String) async throws {
        saves.append(.init(uid: uid, snapshot: snapshot))
        cloud = snapshot
    }

    func observe(
        uid: String,
        onChange: @escaping (Result<AppSettingsSnapshot, Error>) -> Void
    ) -> ObservationToken {
        observedUIDs.append(uid)
        self.onChange = onChange
        let token = SyncFakeObservationToken()
        tokens.append(token)
        return token
    }

    func send(_ snapshot: AppSettingsSnapshot) {
        cloud = snapshot
        onChange?(.success(snapshot))
    }
}

private final class SyncFakeObservationToken: ObservationToken {
    private(set) var cancelCount = 0
    func cancel() { cancelCount += 1 }
}

@MainActor
private final class ManualSettingsSyncScheduler: SettingsSyncDebounceScheduling {
    private struct Scheduled {
        let token: SyncFakeObservationToken
        let operation: @MainActor () async -> Void
    }

    private var scheduled: [Scheduled] = []

    func schedule(_ operation: @escaping @MainActor () async -> Void) -> ObservationToken {
        let token = SyncFakeObservationToken()
        scheduled.append(.init(token: token, operation: operation))
        return token
    }

    func fireAll() async {
        let pending = scheduled
        scheduled.removeAll()
        for item in pending where item.token.cancelCount == 0 {
            await item.operation()
        }
    }
}
