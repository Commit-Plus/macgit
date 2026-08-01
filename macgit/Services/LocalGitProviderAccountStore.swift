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

@MainActor
protocol GitProviderAccountLocalStore {
    var accountOwnerID: String { get }

    func accounts() throws -> [GitProviderAccount]
    func save(_ account: GitProviderAccount) throws
    func delete(accountID: String) throws -> GitProviderAccount?
    func remove(accountID: String) throws
    func pendingDeletions() throws -> [GitProviderAccount]
    func clearPendingDeletion(_ account: GitProviderAccount) throws
    func syncedIdentityKeys(uid: String) -> Set<String>
    func setSyncedIdentityKeys(_ keys: Set<String>, uid: String)
}

@MainActor
final class UserDefaultsGitProviderAccountLocalStore: GitProviderAccountLocalStore {
    let accountOwnerID: String

    private let defaults: UserDefaults
    private let accountsKey: String
    private let pendingDeletionsKey: String
    private let syncedIdentitiesKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        accountsKey: String = "dev.thanhtran.macgit.localGitProviderAccounts",
        pendingDeletionsKey: String = "dev.thanhtran.macgit.localGitProviderAccountPendingDeletions",
        syncedIdentitiesKey: String = "dev.thanhtran.macgit.localGitProviderAccountSyncedIdentities",
        ownerIDKey: String = "dev.thanhtran.macgit.localGitProviderAccountOwnerID"
    ) {
        self.defaults = defaults
        self.accountsKey = accountsKey
        self.pendingDeletionsKey = pendingDeletionsKey
        self.syncedIdentitiesKey = syncedIdentitiesKey

        if let storedOwnerID = defaults.string(forKey: ownerIDKey), !storedOwnerID.isEmpty {
            accountOwnerID = storedOwnerID
        } else {
            let newOwnerID = "local-\(UUID().uuidString)"
            defaults.set(newOwnerID, forKey: ownerIDKey)
            accountOwnerID = newOwnerID
        }
    }

    func accounts() throws -> [GitProviderAccount] {
        guard let data = defaults.data(forKey: accountsKey) else { return [] }
        return try decoder.decode([GitProviderAccount].self, from: data)
    }

    func save(_ account: GitProviderAccount) throws {
        var storedAccounts = try accounts()
        let identity = GitProviderAccountLocalIdentity(account)
        storedAccounts.removeAll {
            $0.id == account.id || GitProviderAccountLocalIdentity($0) == identity
        }
        storedAccounts.append(account)
        try persist(storedAccounts, key: accountsKey)

        var deletions = try pendingDeletions()
        deletions.removeAll { GitProviderAccountLocalIdentity($0) == identity }
        try persist(deletions, key: pendingDeletionsKey)
    }

    func delete(accountID: String) throws -> GitProviderAccount? {
        var storedAccounts = try accounts()
        let deletedAccount = storedAccounts.first { $0.id == accountID }
        storedAccounts.removeAll { $0.id == accountID }
        try persist(storedAccounts, key: accountsKey)

        if let deletedAccount {
            var deletions = try pendingDeletions()
            let identity = GitProviderAccountLocalIdentity(deletedAccount)
            deletions.removeAll { GitProviderAccountLocalIdentity($0) == identity }
            deletions.append(deletedAccount)
            try persist(deletions, key: pendingDeletionsKey)
        }
        return deletedAccount
    }

    func remove(accountID: String) throws {
        var storedAccounts = try accounts()
        storedAccounts.removeAll { $0.id == accountID }
        try persist(storedAccounts, key: accountsKey)
    }

    func pendingDeletions() throws -> [GitProviderAccount] {
        guard let data = defaults.data(forKey: pendingDeletionsKey) else { return [] }
        return try decoder.decode([GitProviderAccount].self, from: data)
    }

    func clearPendingDeletion(_ account: GitProviderAccount) throws {
        var deletions = try pendingDeletions()
        let identity = GitProviderAccountLocalIdentity(account)
        deletions.removeAll { GitProviderAccountLocalIdentity($0) == identity }
        try persist(deletions, key: pendingDeletionsKey)
    }

    func syncedIdentityKeys(uid: String) -> Set<String> {
        let values = defaults.dictionary(forKey: syncedIdentitiesKey) as? [String: [String]] ?? [:]
        return Set(values[uid] ?? [])
    }

    func setSyncedIdentityKeys(_ keys: Set<String>, uid: String) {
        var values = defaults.dictionary(forKey: syncedIdentitiesKey) as? [String: [String]] ?? [:]
        values[uid] = keys.sorted()
        defaults.set(values, forKey: syncedIdentitiesKey)
    }

    private func persist(_ accounts: [GitProviderAccount], key: String) throws {
        defaults.set(try encoder.encode(accounts), forKey: key)
    }
}

@MainActor
final class LocalFirstGitProviderAccountStore: GitProviderAccountStore {
    var accountOwnerID: String { localStore.accountOwnerID }

    private let localStore: GitProviderAccountLocalStore
    private let cloudStore: GitProviderAccountCloudStore?
    private var cloudUID: String?
    private var cloudAccountIDsByLocalAccountID: [String: String] = [:]

    init(
        localStore: GitProviderAccountLocalStore? = nil,
        cloudStore: GitProviderAccountCloudStore?
    ) {
        self.localStore = localStore ?? UserDefaultsGitProviderAccountLocalStore()
        self.cloudStore = cloudStore
    }

    func accounts() async throws -> [GitProviderAccount] {
        try localStore.accounts()
    }

    func updateCloudAccount(uid: String?) async throws {
        cloudUID = uid
        cloudAccountIDsByLocalAccountID = [:]
        guard let uid, let cloudStore else { return }

        let initialLocalAccounts = try localStore.accounts()
        let cloudAccounts: [GitProviderAccount]
        do {
            cloudAccounts = try await cloudStore.accounts(forMacgitUID: uid)
        } catch {
            return
        }

        let pendingDeletions = try localStore.pendingDeletions()
        let pendingIdentities = Set(pendingDeletions.map(GitProviderAccountLocalIdentity.init))
        for deletedAccount in pendingDeletions {
            let identity = GitProviderAccountLocalIdentity(deletedAccount)
            if let cloudAccount = cloudAccounts.first(where: { GitProviderAccountLocalIdentity($0) == identity }) {
                do {
                    try await cloudStore.delete(accountID: cloudAccount.id, macgitUID: uid)
                    try localStore.clearPendingDeletion(deletedAccount)
                } catch {
                    // Keep the tombstone so a stale cloud snapshot cannot restore the local deletion.
                }
            } else {
                try localStore.clearPendingDeletion(deletedAccount)
            }
        }

        let visibleCloudAccounts = cloudAccounts.filter {
            !pendingIdentities.contains(GitProviderAccountLocalIdentity($0))
        }
        let visibleCloudIdentityKeys = Set(visibleCloudAccounts.map {
            GitProviderAccountLocalIdentity($0).storageKey
        })
        let previouslySyncedIdentityKeys = localStore.syncedIdentityKeys(uid: uid)
        for localAccount in initialLocalAccounts {
            let identityKey = GitProviderAccountLocalIdentity(localAccount).storageKey
            if previouslySyncedIdentityKeys.contains(identityKey),
               !visibleCloudIdentityKeys.contains(identityKey),
               !pendingIdentities.contains(GitProviderAccountLocalIdentity(localAccount)) {
                try localStore.remove(accountID: localAccount.id)
            }
        }

        var mergedAccounts = try localStore.accounts()
        for cloudAccount in visibleCloudAccounts {
            let identity = GitProviderAccountLocalIdentity(cloudAccount)
            if let localAccount = mergedAccounts.first(where: {
                GitProviderAccountLocalIdentity($0) == identity
            }) {
                cloudAccountIDsByLocalAccountID[localAccount.id] = cloudAccount.id
            } else {
                try localStore.save(cloudAccount)
                mergedAccounts.append(cloudAccount)
                cloudAccountIDsByLocalAccountID[cloudAccount.id] = cloudAccount.id
            }
        }

        var syncedIdentityKeys = visibleCloudIdentityKeys
        for account in mergedAccounts {
            if await mirrorToCloud(account, uid: uid) {
                syncedIdentityKeys.insert(GitProviderAccountLocalIdentity(account).storageKey)
            }
        }
        localStore.setSyncedIdentityKeys(syncedIdentityKeys, uid: uid)
    }

    func save(_ account: GitProviderAccount) async throws {
        try localStore.save(account)
        guard let cloudUID else { return }
        if await mirrorToCloud(account, uid: cloudUID) {
            var syncedKeys = localStore.syncedIdentityKeys(uid: cloudUID)
            syncedKeys.insert(GitProviderAccountLocalIdentity(account).storageKey)
            localStore.setSyncedIdentityKeys(syncedKeys, uid: cloudUID)
        }
    }

    func delete(accountID: String) async throws {
        guard let deletedAccount = try localStore.delete(accountID: accountID) else { return }
        guard let cloudUID, let cloudStore else { return }

        let cloudAccountID = cloudAccountIDsByLocalAccountID.removeValue(forKey: accountID) ?? accountID
        do {
            try await cloudStore.delete(accountID: cloudAccountID, macgitUID: cloudUID)
            if cloudAccountID != accountID {
                try? await cloudStore.delete(accountID: accountID, macgitUID: cloudUID)
            }
            try localStore.clearPendingDeletion(deletedAccount)
            var syncedKeys = localStore.syncedIdentityKeys(uid: cloudUID)
            syncedKeys.remove(GitProviderAccountLocalIdentity(deletedAccount).storageKey)
            localStore.setSyncedIdentityKeys(syncedKeys, uid: cloudUID)
        } catch {
            // The local deletion is complete; retry the cloud deletion on the next sync.
        }
    }

    private func mirrorToCloud(_ account: GitProviderAccount, uid: String) async -> Bool {
        guard let cloudStore else { return false }

        var cloudAccount = account
        cloudAccount.macgitUID = uid
        do {
            try await cloudStore.save(cloudAccount)
            if let oldCloudID = cloudAccountIDsByLocalAccountID[account.id],
               oldCloudID != account.id {
                try? await cloudStore.delete(accountID: oldCloudID, macgitUID: uid)
            }
            cloudAccountIDsByLocalAccountID[account.id] = account.id
            return true
        } catch {
            // Local metadata and credentials remain authoritative when cloud sync fails.
            return false
        }
    }
}

private struct GitProviderAccountLocalIdentity: Hashable {
    let provider: GitProviderKind
    let host: String
    let providerUserID: String

    var storageKey: String {
        [provider.rawValue, host, providerUserID].joined(separator: "|")
    }

    init(_ account: GitProviderAccount) {
        provider = account.provider
        host = (account.hostURL.host(percentEncoded: false) ?? account.hostURL.absoluteString).lowercased()
        providerUserID = account.providerUserID
    }
}
