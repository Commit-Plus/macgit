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

enum CloudSettingsDocument {
    static func encode(
        _ snapshot: AppSettingsSnapshot,
        updatedAt: Any
    ) -> [String: Any] {
        [
            "schemaVersion": snapshot.schemaVersion,
            "showToolbarButtonText": snapshot.showToolbarButtonText,
            "showSubmodules": snapshot.showSubmodules,
            "showSubtrees": snapshot.showSubtrees,
            "updatedAt": updatedAt
        ]
    }

    static func decode(_ data: [String: Any]?) throws -> AppSettingsSnapshot {
        guard let data,
              let schemaVersion = data["schemaVersion"] as? Int,
              schemaVersion == 1,
              let showToolbarButtonText = data["showToolbarButtonText"] as? Bool,
              let showSubmodules = data["showSubmodules"] as? Bool,
              let showSubtrees = data["showSubtrees"] as? Bool,
              data["updatedAt"] is Timestamp else {
            throw CloudSettingsError.invalidDocument
        }

        return AppSettingsSnapshot(
            showToolbarButtonText: showToolbarButtonText,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees
        )
    }
}

@MainActor
final class FirestoreSettingsStore: CloudSettingsStore {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func load(uid: String) async throws -> AppSettingsSnapshot? {
        let snapshot = try await document(uid: uid).getDocument()
        guard snapshot.exists else { return nil }
        return try CloudSettingsDocument.decode(snapshot.data(with: .estimate))
    }

    func save(_ snapshot: AppSettingsSnapshot, uid: String) async throws {
        try await document(uid: uid).setData(
            CloudSettingsDocument.encode(snapshot, updatedAt: FieldValue.serverTimestamp())
        )
    }

    func observe(
        uid: String,
        onChange: @escaping (Result<AppSettingsSnapshot, Error>) -> Void
    ) -> ObservationToken {
        let registration = document(uid: uid).addSnapshotListener { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }

            do {
                let value = try CloudSettingsDocument.decode(snapshot?.data(with: .estimate))
                onChange(.success(value))
            } catch {
                onChange(.failure(error))
            }
        }
        return SettingsFirestoreObservationToken(registration: registration)
    }

    private func document(uid: String) -> DocumentReference {
        firestore.collection("users").document(uid).collection("settings").document("app")
    }
}

private final class SettingsFirestoreObservationToken: ObservationToken {
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
