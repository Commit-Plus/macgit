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

/// A stable, machine-independent key for the provider account used by a remote.
/// Tokens and SSH keys remain in local credential stores; this key only records
/// the non-secret account preference.
enum GitProviderAccountPreferenceKey {
    static func make(for identity: GitRemoteIdentity) -> String {
        [
            identity.provider.rawValue,
            identity.hostURL.host(percentEncoded: false)?.lowercased() ?? "",
            identity.ownerPath,
            identity.repositoryName,
        ].joined(separator: "|")
    }
}

final class GitProviderAccountPreferenceStore {
    static let shared = GitProviderAccountPreferenceStore()

    private let userDefaults: UserDefaults
    private let key: String
    private var accountIDsByRemoteIdentity: [String: String]

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "dev.thanhtran.macgit.providerAccountPreferences"
    ) {
        self.userDefaults = userDefaults
        self.key = key
        accountIDsByRemoteIdentity = userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    var preferences: [String: String] {
        accountIDsByRemoteIdentity
    }

    func accountID(for identity: GitRemoteIdentity) -> String? {
        accountIDsByRemoteIdentity[GitProviderAccountPreferenceKey.make(for: identity)]
    }

    func update(accountID: String?, for identity: GitRemoteIdentity) {
        update(accountID: accountID, forPreferenceKey: GitProviderAccountPreferenceKey.make(for: identity))
    }

    func update(accountID: String?, forPreferenceKey preferenceKey: String) {
        if let accountID, !accountID.isEmpty {
            accountIDsByRemoteIdentity[preferenceKey] = accountID
        } else {
            accountIDsByRemoteIdentity.removeValue(forKey: preferenceKey)
        }
        save()
    }

    func replacePreferences(_ preferences: [String: String]) {
        accountIDsByRemoteIdentity = preferences.filter { !$0.value.isEmpty }
        save()
    }

    private func save() {
        userDefaults.set(accountIDsByRemoteIdentity, forKey: key)
    }
}
