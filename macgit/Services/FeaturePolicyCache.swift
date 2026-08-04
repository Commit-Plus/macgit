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

struct CachedFeatureAccessPolicy: Codable, Equatable {
    let policy: FeatureAccessPolicy
    let updatedAt: Date
}

@MainActor
protocol FeaturePolicyCaching {
    func load() -> CachedFeatureAccessPolicy?
    func save(_ cachedPolicy: CachedFeatureAccessPolicy)
}

@MainActor
final class UserDefaultsFeaturePolicyCache: FeaturePolicyCaching {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "dev.thanhtran.macgit.featureAccessPolicy"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> CachedFeatureAccessPolicy? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        do {
            let cached = try decoder.decode(CachedFeatureAccessPolicy.self, from: data)
            guard cached.policy.schemaVersion == FeatureAccessPolicy.supportedSchemaVersion else {
                return nil
            }
            return cached
        } catch {
            NSLog("Commit+ feature policy cache could not be decoded: %@", error.localizedDescription)
            return nil
        }
    }

    func save(_ cachedPolicy: CachedFeatureAccessPolicy) {
        do {
            userDefaults.set(try encoder.encode(cachedPolicy), forKey: key)
        } catch {
            NSLog("Commit+ feature policy cache could not be saved: %@", error.localizedDescription)
        }
    }
}
