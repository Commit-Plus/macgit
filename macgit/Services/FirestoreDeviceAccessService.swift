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
import Foundation

@MainActor
final class FirestoreDeviceAccessService: DeviceAccessProviding {
    private let firestore: Firestore

    init(firestore: Firestore = .firestore()) {
        self.firestore = firestore
    }

    func claim(
        uid: String,
        metadata: AccountDeviceMetadata
    ) async throws -> DeviceActivationResult {
        let entitlementReference = firestore.collection("entitlements").document(uid)
        let summaryReference = summaryDocument(uid: uid)
        let deviceReference = deviceDocument(uid: uid, deviceID: metadata.deviceID)

        let rawResult = try await firestore.runTransaction { transaction, errorPointer in
            do {
                let entitlement = try transaction.getDocument(entitlementReference).data()
                let summary = try transaction.getDocument(summaryReference).data()
                let existingDevice = try transaction.getDocument(deviceReference).data()
                let limit = Self.deviceLimit(entitlement: entitlement)
                var activeDeviceIDs = try Self.activeDeviceIDs(summary: summary)

                if !activeDeviceIDs.contains(metadata.deviceID), activeDeviceIDs.count >= limit {
                    return ["status": "limitReached", "limit": limit]
                }

                if !activeDeviceIDs.contains(metadata.deviceID) {
                    activeDeviceIDs.append(metadata.deviceID)
                }

                transaction.setData(
                    [
                        "schemaVersion": 1,
                        "activeDeviceIDs": activeDeviceIDs,
                        "updatedAt": FieldValue.serverTimestamp(),
                    ],
                    forDocument: summaryReference
                )

                var deviceData = metadata.firestorePayload
                deviceData["schemaVersion"] = 1
                deviceData["status"] = AccountDeviceStatus.active.rawValue
                deviceData["lastSeenAt"] = FieldValue.serverTimestamp()
                deviceData["createdAt"] = existingDevice?["createdAt"] ?? FieldValue.serverTimestamp()
                deviceData["revokedAt"] = FieldValue.delete()
                deviceData["revokedReason"] = FieldValue.delete()
                transaction.setData(deviceData, forDocument: deviceReference, merge: true)

                return [
                    "status": "active",
                    "limit": limit,
                    "createdAt": existingDevice?["createdAt"] as Any,
                ]
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard let result = rawResult as? [String: Any],
              let status = result["status"] as? String,
              let limit = (result["limit"] as? NSNumber)?.intValue ?? result["limit"] as? Int else {
            throw DeviceAccessError(message: "Commit+ could not verify this Mac's device slot.")
        }
        if status == "limitReached" {
            return .limitReached(limit: limit)
        }
        guard status == "active" else {
            throw DeviceAccessError(message: "Commit+ received an invalid device-access result.")
        }
        let createdAt = (result["createdAt"] as? Timestamp)?.dateValue() ?? .now
        return .active(
            limit: limit,
            device: AccountDevice(
                id: metadata.deviceID,
                modelFamily: metadata.modelFamily,
                osVersion: metadata.osVersion,
                appVersion: metadata.appVersion,
                status: .active,
                createdAt: createdAt,
                lastSeenAt: .now,
                revokedAt: nil,
                revokedReason: nil
            )
        )
    }

    func release(uid: String, deviceID: String) async throws {
        let summaryReference = summaryDocument(uid: uid)
        let deviceReference = deviceDocument(uid: uid, deviceID: deviceID)
        _ = try await firestore.runTransaction { transaction, errorPointer in
            do {
                let summary = try transaction.getDocument(summaryReference).data()
                let activeDeviceIDs = try Self.activeDeviceIDs(summary: summary)
                guard activeDeviceIDs.contains(deviceID) else { return nil }

                transaction.setData(
                    [
                        "schemaVersion": 1,
                        "activeDeviceIDs": activeDeviceIDs.filter { $0 != deviceID },
                        "updatedAt": FieldValue.serverTimestamp(),
                    ],
                    forDocument: summaryReference
                )
                transaction.setData(
                    [
                        "status": AccountDeviceStatus.revoked.rawValue,
                        "revokedAt": FieldValue.serverTimestamp(),
                        "revokedReason": AccountDeviceRevocationReason.signedOut.rawValue,
                    ],
                    forDocument: deviceReference,
                    merge: true
                )
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    func observeCurrentDevice(
        uid: String,
        deviceID: String,
        onChange: @escaping @MainActor (AccountDeviceObservationState) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) -> ObservationToken {
        let registration = deviceDocument(uid: uid, deviceID: deviceID)
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
                        let device = try Self.decodeDevice(
                            data.merging(["deviceID": deviceID]) { value, _ in value }
                        )
                        onChange(
                            device.status == .active
                                ? .active(device)
                                : .revoked(device.revokedReason)
                        )
                    } catch {
                        onError(error.localizedDescription)
                    }
                }
            }
        return DeviceFirestoreObservationToken(registration: registration)
    }

    private func summaryDocument(uid: String) -> DocumentReference {
        firestore.collection("users").document(uid).collection("deviceAccess").document("summary")
    }

    private func deviceDocument(uid: String, deviceID: String) -> DocumentReference {
        firestore.collection("users").document(uid).collection("devices").document(deviceID)
    }

    private static func deviceLimit(entitlement: [String: Any]?) -> Int {
        entitlement?["plan"] as? String == "pro"
            && entitlement?["access"] as? String == "active"
            ? 3
            : 1
    }

    private static func activeDeviceIDs(summary: [String: Any]?) throws -> [String] {
        guard let summary else { return [] }
        guard summary["schemaVersion"] as? Int == 1,
              let deviceIDs = summary["activeDeviceIDs"] as? [String],
              deviceIDs.count <= 3,
              Set(deviceIDs).count == deviceIDs.count else {
            throw DeviceAccessError(message: "The Commit+ device registry is invalid.")
        }
        return deviceIDs
    }

    private static func decodeDevice(_ payload: [String: Any]) throws -> AccountDevice {
        guard let deviceID = payload["deviceID"] as? String,
              let modelFamily = payload["modelFamily"] as? String,
              let osVersion = payload["osVersion"] as? String,
              let appVersion = payload["appVersion"] as? String,
              let rawStatus = payload["status"] as? String,
              let status = AccountDeviceStatus(rawValue: rawStatus) else {
            throw DeviceAccessError(message: "Commit+ received invalid device information.")
        }
        return AccountDevice(
            id: deviceID,
            modelFamily: modelFamily,
            osVersion: osVersion,
            appVersion: appVersion,
            status: status,
            createdAt: (payload["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            lastSeenAt: (payload["lastSeenAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            revokedAt: (payload["revokedAt"] as? Timestamp)?.dateValue(),
            revokedReason: (payload["revokedReason"] as? String)
                .flatMap(AccountDeviceRevocationReason.init(rawValue:))
        )
    }
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
