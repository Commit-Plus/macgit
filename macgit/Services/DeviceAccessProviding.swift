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

enum AccountDeviceObservationState: Equatable, Sendable {
    case active(AccountDevice)
    case revoked(AccountDeviceRevocationReason?)
    case missing
}

struct AccountDeviceList: Equatable, Sendable {
    let limit: Int
    let devices: [AccountDevice]
}

struct DeviceAccessError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
protocol DeviceAccessProviding {
    func claim(_ metadata: AccountDeviceMetadata) async throws -> DeviceActivationResult
    func replace(
        replacing deviceID: String,
        with metadata: AccountDeviceMetadata
    ) async throws -> DeviceActivationResult
    func releaseCurrentDevice() async throws
    func revoke(deviceID: String) async throws
    func heartbeat(_ metadata: AccountDeviceMetadata) async throws
    func listDevices() async throws -> AccountDeviceList
    func observeCurrentDevice(
        uid: String,
        deviceID: String,
        onChange: @escaping @MainActor (AccountDeviceObservationState) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) -> ObservationToken
}
