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

struct CachedRepositoryVisibility: Codable, Equatable {
    let provider: GitProviderKind
    let host: String
    let owner: String
    let name: String
    let visibility: RepositoryVisibility
    let resolvedAt: Date

    init(
        repository: GitRepositoryIdentity,
        visibility: RepositoryVisibility,
        resolvedAt: Date
    ) {
        provider = repository.provider
        host = Self.normalizedHost(repository.hostURL)
        owner = repository.owner.lowercased()
        name = repository.name.lowercased()
        self.visibility = visibility
        self.resolvedAt = resolvedAt
    }

    var cacheKey: String {
        [provider.rawValue, host, owner, name].joined(separator: "|")
    }

    static func cacheKey(for repository: GitRepositoryIdentity) -> String {
        [
            repository.provider.rawValue,
            normalizedHost(repository.hostURL),
            repository.owner.lowercased(),
            repository.name.lowercased(),
        ].joined(separator: "|")
    }

    private static func normalizedHost(_ url: URL) -> String {
        (url.host(percentEncoded: false) ?? url.absoluteString).lowercased()
    }
}

@MainActor
protocol RepositoryVisibilityCaching {
    func cachedVisibility(
        for repository: GitRepositoryIdentity,
        maximumAge: TimeInterval,
        now: Date
    ) -> RepositoryVisibility?

    func save(
        _ visibility: RepositoryVisibility,
        for repository: GitRepositoryIdentity,
        resolvedAt: Date
    )
}

@MainActor
final class UserDefaultsRepositoryVisibilityCache: RepositoryVisibilityCaching {
    private let userDefaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "dev.thanhtran.macgit.repositoryVisibility"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func cachedVisibility(
        for repository: GitRepositoryIdentity,
        maximumAge: TimeInterval,
        now: Date
    ) -> RepositoryVisibility? {
        let record = loadAll()[CachedRepositoryVisibility.cacheKey(for: repository)]
        guard let record,
              record.visibility == .public || record.visibility == .private,
              now.timeIntervalSince(record.resolvedAt) >= 0,
              now.timeIntervalSince(record.resolvedAt) <= maximumAge else {
            return nil
        }
        return record.visibility
    }

    func save(
        _ visibility: RepositoryVisibility,
        for repository: GitRepositoryIdentity,
        resolvedAt: Date
    ) {
        guard visibility == .public || visibility == .private else { return }
        let record = CachedRepositoryVisibility(
            repository: repository,
            visibility: visibility,
            resolvedAt: resolvedAt
        )
        var values = loadAll()
        values[record.cacheKey] = record
        do {
            userDefaults.set(try encoder.encode(values), forKey: key)
        } catch {
            NSLog("Commit+ repository visibility cache could not be saved: %@", error.localizedDescription)
        }
    }

    private func loadAll() -> [String: CachedRepositoryVisibility] {
        guard let data = userDefaults.data(forKey: key) else { return [:] }
        do {
            return try decoder.decode([String: CachedRepositoryVisibility].self, from: data)
        } catch {
            NSLog("Commit+ repository visibility cache could not be decoded: %@", error.localizedDescription)
            return [:]
        }
    }
}
