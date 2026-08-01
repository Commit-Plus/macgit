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

struct CachedAccountEntitlement: Codable, Equatable {
    let entitlement: AccountEntitlement
    let updatedAt: Date
}

@MainActor
protocol EntitlementCaching {
    func cachedEntitlement(for uid: String) -> CachedAccountEntitlement?
    func save(_ cachedEntitlement: CachedAccountEntitlement, for uid: String)
    func removeEntitlement(for uid: String)
}

@MainActor
final class UserDefaultsEntitlementCache: EntitlementCaching {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "dev.thanhtran.macgit.accountEntitlements"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func cachedEntitlement(for uid: String) -> CachedAccountEntitlement? {
        loadAll()[uid]
    }

    func save(_ cachedEntitlement: CachedAccountEntitlement, for uid: String) {
        var entitlements = loadAll()
        entitlements[uid] = cachedEntitlement
        persist(entitlements)
    }

    func removeEntitlement(for uid: String) {
        var entitlements = loadAll()
        entitlements.removeValue(forKey: uid)
        persist(entitlements)
    }

    private func loadAll() -> [String: CachedAccountEntitlement] {
        guard let data = userDefaults.data(forKey: key) else { return [:] }

        do {
            return try decoder.decode([String: CachedAccountEntitlement].self, from: data)
        } catch {
            NSLog("Commit+ entitlement cache could not be decoded: %@", error.localizedDescription)
            return [:]
        }
    }

    private func persist(_ entitlements: [String: CachedAccountEntitlement]) {
        do {
            userDefaults.set(try encoder.encode(entitlements), forKey: key)
        } catch {
            NSLog("Commit+ entitlement cache could not be saved: %@", error.localizedDescription)
        }
    }
}
