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

import Darwin
import Foundation
import Security

@MainActor
protocol DeviceIdentityProviding {
    func currentDevice() throws -> AccountDeviceMetadata
}

protocol DeviceIdentifierStoring {
    func readIdentifier() throws -> String?
    func saveIdentifier(_ identifier: String) throws
}

struct DeviceIdentityError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

final class KeychainDeviceIdentifierStore: DeviceIdentifierStoring {
    private let service: String
    private let account = "commit-plus-device-id"

    init(service: String = "dev.thanhtran.macgit.commit-plus-device") {
        self.service = service
    }

    func readIdentifier() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let identifier = String(data: data, encoding: .utf8) else {
            throw keychainError(status == errSecSuccess ? errSecDecode : status)
        }
        return identifier
    }

    func saveIdentifier(_ identifier: String) throws {
        guard let data = identifier.data(using: .utf8) else {
            throw DeviceIdentityError(message: "Commit+ could not encode this Mac's device identifier.")
        }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else { throw keychainError(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw keychainError(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainError(_ status: OSStatus) -> DeviceIdentityError {
        let detail = SecCopyErrorMessageString(status, nil) as String?
            ?? "Keychain error \(status)"
        return DeviceIdentityError(
            message: "Commit+ could not access this Mac's device identity. \(detail)"
        )
    }
}

@MainActor
final class CommitPlusDeviceIdentityProvider: DeviceIdentityProviding {
    private let store: DeviceIdentifierStoring
    private let modelFamily: () -> String
    private let operatingSystemVersion: () -> OperatingSystemVersion
    private let appVersion: () -> String

    init(
        store: DeviceIdentifierStoring = KeychainDeviceIdentifierStore(),
        modelFamily: @escaping () -> String = MacModelFamily.current,
        operatingSystemVersion: @escaping () -> OperatingSystemVersion = {
            ProcessInfo.processInfo.operatingSystemVersion
        },
        appVersion: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "Unknown"
        }
    ) {
        self.store = store
        self.modelFamily = modelFamily
        self.operatingSystemVersion = operatingSystemVersion
        self.appVersion = appVersion
    }

    func currentDevice() throws -> AccountDeviceMetadata {
        let identifier: String
        if let storedIdentifier = try store.readIdentifier(),
           UUID(uuidString: storedIdentifier) != nil {
            identifier = storedIdentifier.lowercased()
        } else {
            identifier = UUID().uuidString.lowercased()
            try store.saveIdentifier(identifier)
        }

        let version = operatingSystemVersion()
        return AccountDeviceMetadata(
            deviceID: identifier,
            modelFamily: modelFamily(),
            osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            appVersion: appVersion()
        )
    }
}

enum MacModelFamily {
    static func current() -> String {
        guard let modelIdentifier = hardwareModelIdentifier() else { return "Mac" }
        if modelIdentifier.hasPrefix("MacBookPro") { return "MacBook Pro" }
        if modelIdentifier.hasPrefix("MacBookAir") { return "MacBook Air" }
        if modelIdentifier.hasPrefix("MacBook") { return "MacBook" }
        if modelIdentifier.hasPrefix("Macmini") { return "Mac mini" }
        if modelIdentifier.hasPrefix("MacStudio") { return "Mac Studio" }
        if modelIdentifier.hasPrefix("MacPro") { return "Mac Pro" }
        if modelIdentifier.hasPrefix("iMac") { return "iMac" }
        return "Mac"
    }

    private static func hardwareModelIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname("hw.model", bytes.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        return String(cString: buffer)
    }
}

@MainActor
protocol AccountDeviceSessionCaching {
    func session(for uid: String) -> CachedAccountDeviceSession?
    func save(_ session: CachedAccountDeviceSession)
    func removeSession(for uid: String)
}

@MainActor
final class UserDefaultsAccountDeviceSessionCache: AccountDeviceSessionCaching {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "dev.thanhtran.macgit.accountDeviceSessions"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func session(for uid: String) -> CachedAccountDeviceSession? {
        loadAll()[uid]
    }

    func save(_ session: CachedAccountDeviceSession) {
        var sessions = loadAll()
        sessions[session.uid] = session
        persist(sessions)
    }

    func removeSession(for uid: String) {
        var sessions = loadAll()
        sessions.removeValue(forKey: uid)
        persist(sessions)
    }

    private func loadAll() -> [String: CachedAccountDeviceSession] {
        guard let data = userDefaults.data(forKey: key) else { return [:] }
        do {
            return try decoder.decode([String: CachedAccountDeviceSession].self, from: data)
        } catch {
            NSLog("Commit+ device-session cache could not be decoded: %@", error.localizedDescription)
            return [:]
        }
    }

    private func persist(_ sessions: [String: CachedAccountDeviceSession]) {
        do {
            userDefaults.set(try encoder.encode(sessions), forKey: key)
        } catch {
            NSLog("Commit+ device-session cache could not be saved: %@", error.localizedDescription)
        }
    }
}
