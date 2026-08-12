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
final class FirebaseDeviceAccessServiceTests: XCTestCase {
    func testDecodesActiveClaimResult() throws {
        let payload: [String: Any] = [
            "status": "active",
            "limit": NSNumber(value: 3),
            "device": devicePayload,
            "devices": [devicePayload],
            "customToken": "custom-token",
        ]

        let result = try FirebaseDeviceAccessService.decodeActivationResult(payload)

        guard case .active(let limit, let device, let devices, let token) = result else {
            return XCTFail("Expected active device result")
        }
        XCTAssertEqual(limit, 3)
        XCTAssertEqual(device.id, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        XCTAssertEqual(devices, [device])
        XCTAssertEqual(token, "custom-token")
        XCTAssertEqual(device.lastSeenAt, Date(timeIntervalSince1970: 2))
    }

    func testDecodesLimitReachedWithoutToken() throws {
        let result = try FirebaseDeviceAccessService.decodeActivationResult([
            "status": "limitReached",
            "limit": 1,
            "devices": [devicePayload],
        ])

        guard case .limitReached(let limit, let devices) = result else {
            return XCTFail("Expected limit-reached result")
        }
        XCTAssertEqual(limit, 1)
        XCTAssertEqual(devices.count, 1)
    }

    func testMalformedResponseFailsClosed() {
        XCTAssertThrowsError(
            try FirebaseDeviceAccessService.decodeActivationResult([
                "status": "active",
                "limit": 1,
                "devices": [],
            ])
        )
    }

    private var devicePayload: [String: Any] {
        [
            "deviceID": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "modelFamily": "MacBook Pro",
            "osVersion": "15.6.0",
            "appVersion": "1.0",
            "status": "active",
            "createdAtMillis": NSNumber(value: 1_000),
            "lastSeenAtMillis": NSNumber(value: 2_000),
        ]
    }
}
