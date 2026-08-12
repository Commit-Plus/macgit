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

struct AccountDeviceMetadata: Equatable, Sendable {
    let deviceID: String
    let modelFamily: String
    let osVersion: String
    let appVersion: String

    var firestorePayload: [String: Any] {
        [
            "deviceID": deviceID,
            "platform": "macOS",
            "modelFamily": modelFamily,
            "osVersion": osVersion,
            "appVersion": appVersion,
        ]
    }
}

enum AccountDeviceStatus: String, Equatable, Sendable {
    case active
    case revoked
}

enum AccountDeviceRevocationReason: String, Equatable, Sendable {
    case signedOut
    case replaced
    case planDowngrade
    case userRevoked
    case accountDeleted

    var message: String {
        switch self {
        case .signedOut:
            "This Mac was signed out of the Commit+ account."
        case .replaced:
            "This Mac was replaced by another Mac on the Commit+ account."
        case .planDowngrade:
            "This Mac was signed out because the account's device limit changed."
        case .userRevoked:
            "This Mac was removed from the Commit+ account."
        case .accountDeleted:
            "The Commit+ account is no longer available."
        }
    }
}

struct AccountDevice: Identifiable, Equatable, Sendable {
    let id: String
    let modelFamily: String
    let osVersion: String
    let appVersion: String
    let status: AccountDeviceStatus
    let createdAt: Date
    let lastSeenAt: Date
    let revokedAt: Date?
    let revokedReason: AccountDeviceRevocationReason?

    func isCurrent(_ metadata: AccountDeviceMetadata) -> Bool {
        id == metadata.deviceID
    }
}

enum DeviceActivationResult: Equatable, Sendable {
    case active(limit: Int, device: AccountDevice)
    case limitReached(limit: Int)
}

enum AccountDeviceVerification: Equatable, Sendable {
    case live
    case cached
}

enum AccountDeviceAccessState: Equatable, Sendable {
    case unavailable
    case unverified
    case verifying
    case active(limit: Int, device: AccountDevice, verification: AccountDeviceVerification)
    case limitReached(limit: Int)
    case revoked(AccountDeviceRevocationReason?)
    case failed(message: String, mayRetry: Bool)

    var reachedLimit: Int? {
        guard case .limitReached(let limit) = self else { return nil }
        return limit
    }

    var activeLimit: Int? {
        guard case .active(let limit, _, _) = self else { return nil }
        return limit
    }
}

struct CachedAccountDeviceSession: Codable, Equatable, Sendable {
    let uid: String
    let deviceID: String
    let verifiedAt: Date
}
