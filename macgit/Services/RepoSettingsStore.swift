//
//  RepoSettingsStore.swift
//  macgit
//

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

final class RepoSettingsStore {
    static let shared = RepoSettingsStore()

    private let userDefaults: UserDefaults
    private let key: String
    private var settings: [String: RepoSettings]

    init(userDefaults: UserDefaults = .standard, key: String = "dev.thanhtran.macgit.repoSettings") {
        self.userDefaults = userDefaults
        self.key = key
        if let data = userDefaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: RepoSettings].self, from: data) {
            settings = decoded
        } else {
            settings = [:]
        }
    }

    func settings(for repositoryPath: String, currentBranch: String?, remotes: [String]) -> RepoSettings {
        settings[repositoryPath] ?? RepoSettings.defaults(currentBranch: currentBranch, remotes: remotes)
    }

    func update(for repositoryPath: String, settings: RepoSettings) {
        self.settings[repositoryPath] = settings
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }
}
