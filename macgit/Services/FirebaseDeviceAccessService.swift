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

import FirebaseFirestore
import FirebaseFunctions
import Foundation

@MainActor
final class FirebaseDeviceAccessService: DeviceAccessProviding {
    private let functions: Functions
    private let firestore: Firestore

    init(
        functions: Functions = .functions(),
        firestore: Firestore = .firestore()
    ) {
        self.functions = functions
        self.firestore = firestore
    }

    func claim(_ metadata: AccountDeviceMetadata) async throws -> DeviceActivationResult {
        let result = try await functions.httpsCallable("claimCommitPlusDevice").call(metadata.callablePayload)
        return try Self.decodeActivationResult(result.data)
    }

    func replace(
        replacing deviceID: String,
        with metadata: AccountDeviceMetadata
    ) async throws -> DeviceActivationResult {
        let payload: [String: Any] = [
            "replacingDeviceID": deviceID,
            "device": metadata.callablePayload,
        ]
        let result = try await functions.httpsCallable("replaceCommitPlusDevice").call(payload)
        return try Self.decodeActivationResult(result.data)
    }

    func releaseCurrentDevice() async throws {
        _ = try await functions.httpsCallable("releaseCommitPlusDevice").call()
    }

    func revoke(deviceID: String) async throws {
        _ = try await functions.httpsCallable("revokeCommitPlusDevice").call(["deviceID": deviceID])
    }

    func heartbeat(_ metadata: AccountDeviceMetadata) async throws {
        _ = try await functions.httpsCallable("heartbeatCommitPlusDevice").call(metadata.callablePayload)
    }

    func listDevices() async throws -> AccountDeviceList {
        let result = try await functions.httpsCallable("listCommitPlusDevices").call()
        guard let payload = result.data as? [String: Any],
              let limit = Self.integer(payload["limit"]),
              let rawDevices = payload["devices"] as? [Any] else {
            throw Self.invalidResponse
        }
        return AccountDeviceList(limit: limit, devices: try rawDevices.map(Self.decodeDevice))
    }

    func observeCurrentDevice(
        uid: String,
        deviceID: String,
        onChange: @escaping @MainActor (AccountDeviceObservationState) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) -> ObservationToken {
        let registration = firestore
            .collection("users")
            .document(uid)
            .collection("devices")
            .document(deviceID)
            .addSnapshotListener { snapshot, error in
                Task { @MainActor in
                    if let error {
                        onError(error.localizedDescription)
                        return
                    }
                    guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                        onChange(.missing)
                        return
                    }
                    do {
                        let device = try Self.decodeFirestoreDevice(
                            data.merging(["deviceID": deviceID]) { value, _ in value }
                        )
                        if device.status == .active {
                            onChange(.active(device))
                        } else {
                            onChange(.revoked(device.revokedReason))
                        }
                    } catch {
                        onError(error.localizedDescription)
                    }
                }
            }
        return DeviceFirestoreObservationToken(registration: registration)
    }

    static func decodeActivationResult(_ value: Any) throws -> DeviceActivationResult {
        guard let payload = value as? [String: Any],
              let status = payload["status"] as? String,
              let limit = integer(payload["limit"]),
              let rawDevices = payload["devices"] as? [Any] else {
            throw invalidResponse
        }
        let devices = try rawDevices.map(decodeDevice)
        if status == "limitReached" {
            return .limitReached(limit: limit, devices: devices)
        }
        guard status == "active",
              let rawDevice = payload["device"],
              let customToken = payload["customToken"] as? String,
              !customToken.isEmpty else {
            throw invalidResponse
        }
        return .active(
            limit: limit,
            device: try decodeDevice(rawDevice),
            devices: devices,
            customToken: customToken
        )
    }

    static func decodeDevice(_ value: Any) throws -> AccountDevice {
        guard let payload = value as? [String: Any],
              let deviceID = payload["deviceID"] as? String,
              let modelFamily = payload["modelFamily"] as? String,
              let osVersion = payload["osVersion"] as? String,
              let appVersion = payload["appVersion"] as? String,
              let rawStatus = payload["status"] as? String,
              let status = AccountDeviceStatus(rawValue: rawStatus),
              let createdAtMillis = double(payload["createdAtMillis"]),
              let lastSeenAtMillis = double(payload["lastSeenAtMillis"]) else {
            throw invalidResponse
        }
        let revokedAt = double(payload["revokedAtMillis"]).map {
            Date(timeIntervalSince1970: $0 / 1_000)
        }
        let revokedReason = (payload["revokedReason"] as? String)
            .flatMap(AccountDeviceRevocationReason.init(rawValue:))
        return AccountDevice(
            id: deviceID,
            modelFamily: modelFamily,
            osVersion: osVersion,
            appVersion: appVersion,
            status: status,
            createdAt: Date(timeIntervalSince1970: createdAtMillis / 1_000),
            lastSeenAt: Date(timeIntervalSince1970: lastSeenAtMillis / 1_000),
            revokedAt: revokedAt,
            revokedReason: revokedReason
        )
    }

    static func decodeFirestoreDevice(_ payload: [String: Any]) throws -> AccountDevice {
        guard let deviceID = payload["deviceID"] as? String,
              let modelFamily = payload["modelFamily"] as? String,
              let osVersion = payload["osVersion"] as? String,
              let appVersion = payload["appVersion"] as? String,
              let rawStatus = payload["status"] as? String,
              let status = AccountDeviceStatus(rawValue: rawStatus) else {
            throw invalidResponse
        }
        let createdAt = (payload["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        let lastSeenAt = (payload["lastSeenAt"] as? Timestamp)?.dateValue() ?? createdAt
        let revokedAt = (payload["revokedAt"] as? Timestamp)?.dateValue()
        let revokedReason = (payload["revokedReason"] as? String)
            .flatMap(AccountDeviceRevocationReason.init(rawValue:))
        return AccountDevice(
            id: deviceID,
            modelFamily: modelFamily,
            osVersion: osVersion,
            appVersion: appVersion,
            status: status,
            createdAt: createdAt,
            lastSeenAt: lastSeenAt,
            revokedAt: revokedAt,
            revokedReason: revokedReason
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return value as? Double
    }

    private static let invalidResponse = DeviceAccessError(
        message: "Commit+ received an invalid device-access response. Try again."
    )
}

private final class DeviceFirestoreObservationToken: ObservationToken {
    private var registration: ListenerRegistration?

    init(registration: ListenerRegistration) {
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit {
        registration?.remove()
    }
}
