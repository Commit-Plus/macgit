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
final class DeviceIdentityStoreTests: XCTestCase {
    func testGeneratedIdentifierIsRandomUUIDAndStableInThisInstallation() throws {
        let store = MemoryDeviceIdentifierStore()
        let provider = makeProvider(store: store)

        let first = try provider.currentDevice()
        let second = try provider.currentDevice()

        XCTAssertNotNil(UUID(uuidString: first.deviceID))
        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertEqual(store.savedIdentifiers, [first.deviceID])
    }

    func testInvalidStoredIdentifierIsReplaced() throws {
        let store = MemoryDeviceIdentifierStore(identifier: "hardware-fingerprint")
        let provider = makeProvider(store: store)

        let metadata = try provider.currentDevice()

        XCTAssertNotEqual(metadata.deviceID, "hardware-fingerprint")
        XCTAssertNotNil(UUID(uuidString: metadata.deviceID))
    }

    func testServerPayloadContainsOnlyRandomIdentifierAndGenericMetadata() throws {
        let metadata = try makeProvider(store: MemoryDeviceIdentifierStore()).currentDevice()

        XCTAssertEqual(
            Set(metadata.callablePayload.keys),
            ["deviceID", "platform", "modelFamily", "osVersion", "appVersion"]
        )
        XCTAssertEqual(metadata.modelFamily, "MacBook Pro")
        XCTAssertFalse(metadata.callablePayload.keys.contains("serial"))
        XCTAssertFalse(metadata.callablePayload.keys.contains("macAddress"))
        XCTAssertFalse(metadata.callablePayload.keys.contains("fingerprint"))
    }

    private func makeProvider(store: MemoryDeviceIdentifierStore) -> CommitPlusDeviceIdentityProvider {
        CommitPlusDeviceIdentityProvider(
            store: store,
            modelFamily: { "MacBook Pro" },
            operatingSystemVersion: {
                OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 0)
            },
            appVersion: { "1.0" }
        )
    }
}

private final class MemoryDeviceIdentifierStore: DeviceIdentifierStoring {
    private var identifier: String?
    private(set) var savedIdentifiers: [String] = []

    init(identifier: String? = nil) {
        self.identifier = identifier
    }

    func readIdentifier() throws -> String? { identifier }

    func saveIdentifier(_ identifier: String) throws {
        self.identifier = identifier
        savedIdentifiers.append(identifier)
    }
}
