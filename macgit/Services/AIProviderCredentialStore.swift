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
import Security

protocol AIProviderCredentialStore: Sendable {
    func apiKey(for providerID: AIProviderID) throws -> String?
    func saveAPIKey(_ apiKey: String, for providerID: AIProviderID) throws
    func deleteAPIKey(for providerID: AIProviderID) throws
}

struct AIProviderCredentialStoreError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}

final class KeychainAIProviderCredentialStore: AIProviderCredentialStore, @unchecked Sendable {
    private let service = "com.commitplus.macgit.ai-provider-api-keys"

    func apiKey(for providerID: AIProviderID) throws -> String? {
        var query = baseQuery(for: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AIProviderCredentialStoreError(status: status)
        }
        guard let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8),
              !apiKey.isEmpty else {
            throw AIProviderCredentialStoreError(status: errSecDecode)
        }
        return apiKey
    }

    func saveAPIKey(_ apiKey: String, for providerID: AIProviderID) throws {
        let data = Data(apiKey.utf8)
        var item = baseQuery(for: providerID)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(for: providerID) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw AIProviderCredentialStoreError(status: updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw AIProviderCredentialStoreError(status: status)
        }
    }

    func deleteAPIKey(for providerID: AIProviderID) throws {
        let status = SecItemDelete(baseQuery(for: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIProviderCredentialStoreError(status: status)
        }
    }

    private func baseQuery(for providerID: AIProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID.rawValue,
        ]
    }
}
