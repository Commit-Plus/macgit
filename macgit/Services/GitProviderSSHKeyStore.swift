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

struct GitProviderSSHKey: Equatable, Codable {
    var path: String
}

protocol GitProviderSSHKeyStore {
    func key(for account: GitProviderAccount) throws -> GitProviderSSHKey?
    func saveKey(_ key: GitProviderSSHKey, for account: GitProviderAccount) throws
    func deleteKey(for account: GitProviderAccount) throws
}

enum GitProviderSSHKeyStoreKey {
    private static let prefix = "gitProviderSSHKey"

    static func key(for account: GitProviderAccount) -> String {
        GitProviderTokenVaultKey.key(for: account)
    }

    static func storageKey(for account: GitProviderAccount) -> String {
        "\(prefix).\(key(for: account))"
    }
}

struct UserDefaultsGitProviderSSHKeyStore: GitProviderSSHKeyStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func key(for account: GitProviderAccount) throws -> GitProviderSSHKey? {
        guard let data = defaults.data(forKey: GitProviderSSHKeyStoreKey.storageKey(for: account)) else {
            return nil
        }
        return try decoder.decode(GitProviderSSHKey.self, from: data)
    }

    func saveKey(_ key: GitProviderSSHKey, for account: GitProviderAccount) throws {
        let data = try encoder.encode(key)
        defaults.set(data, forKey: GitProviderSSHKeyStoreKey.storageKey(for: account))
    }

    func deleteKey(for account: GitProviderAccount) throws {
        defaults.removeObject(forKey: GitProviderSSHKeyStoreKey.storageKey(for: account))
    }
}
