import FirebaseFirestore
import Foundation

enum EntitlementDocumentDecoder {
    static func decode(
        _ data: [String: Any]?,
        onDiagnostic: ((String) -> Void)? = nil
    ) -> AccountEntitlement {
        guard let data else { return .free }
        guard let planRaw = data["plan"] as? String,
              let plan = AccountPlan(rawValue: planRaw),
              let accessRaw = data["access"] as? String,
              let access = EntitlementAccess(rawValue: accessRaw),
              let statusRaw = data["billingStatus"] as? String,
              let status = BillingStatus(rawValue: statusRaw) else {
            onDiagnostic?("The entitlement document is malformed; defaulting to Free.")
            return .free
        }

        return AccountEntitlement(
            plan: plan,
            access: access,
            billingStatus: status,
            source: (data["source"] as? String).flatMap(EntitlementSource.init(rawValue:)),
            currentPeriodEnd: (data["currentPeriodEnd"] as? Timestamp)?.dateValue(),
            cancelAtPeriodEnd: data["cancelAtPeriodEnd"] as? Bool ?? false
        )
    }
}

@MainActor
final class FirestoreEntitlementStore: EntitlementProviding {
    private let firestore: Firestore

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
    }

    func observe(
        uid: String,
        onChange: @escaping (AccountEntitlement) -> Void,
        onError: @escaping (String) -> Void
    ) -> ObservationToken {
        let registration = firestore.collection("entitlements").document(uid)
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error.localizedDescription)
                    return
                }
                let entitlement = EntitlementDocumentDecoder.decode(
                    snapshot?.data(),
                    onDiagnostic: { diagnostic in
                        NSLog("Commit+ entitlement: %@", diagnostic)
                    }
                )
                onChange(entitlement)
            }
        return FirestoreObservationToken(registration: registration)
    }
}

private final class FirestoreObservationToken: ObservationToken {
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
+//
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

