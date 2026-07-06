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

import Combine
import Foundation

@MainActor
final class GitProviderAccountController: ObservableObject {
    @Published private(set) var accounts: [GitProviderAccount] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let store: GitProviderAccountStore
    private let tokenVault: GitProviderTokenVault
    private var macgitUID: String?

    init(store: GitProviderAccountStore, tokenVault: GitProviderTokenVault) {
        self.store = store
        self.tokenVault = tokenVault
    }

    func updateMacgitAccount(_ account: AccountSnapshot?) async {
        macgitUID = account?.uid
        guard account != nil else {
            accounts = []
            errorMessage = nil
            isLoading = false
            return
        }
        await reload()
    }

    func reload() async {
        guard let macgitUID else {
            accounts = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let storedAccounts = try await store.accounts(forMacgitUID: macgitUID)
            accounts = try storedAccounts.map { account in
                guard try tokenVault.readToken(for: account) != nil else {
                    var unavailableAccount = account
                    unavailableAccount.tokenStatus = .unavailableOnThisDevice
                    return unavailableAccount
                }
                return account
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect(_ account: GitProviderAccount) async {
        guard macgitUID == account.macgitUID else { return }

        errorMessage = nil
        do {
            try tokenVault.deleteToken(for: account)
            try await store.delete(accountID: account.id, macgitUID: account.macgitUID)
            accounts.removeAll { $0.id == account.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
