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
import SwiftUI
import Combine

enum FileMenuAction: Equatable {
    case new
    case open
    case close
    case openRecent(URL)
}

final class AppState: ObservableObject {
    static let shared = AppState()
    private static let showToolbarButtonTextKey = "showToolbarButtonText"
    private static let showSubmodulesKey = "showSubmodules"
    private static let showSubtreesKey = "showSubtrees"
    private static let settingsSyncEnabledKey = "settingsSyncEnabled"
    private static let searchFilterKey = "searchFilter"

    private let userDefaults: UserDefaults

    @Published var fileMenuAction: FileMenuAction?
    @Published var openWindowWithCloneSheet = false
    @Published var newWindowRepoURL: URL?
    @Published var hasOpenRepository = false
    @Published var showToolbarButtonText: Bool {
        didSet {
            userDefaults.set(showToolbarButtonText, forKey: Self.showToolbarButtonTextKey)
        }
    }
    @Published var showSubmodules: Bool {
        didSet {
            userDefaults.set(showSubmodules, forKey: Self.showSubmodulesKey)
        }
    }
    @Published var showSubtrees: Bool {
        didSet {
            userDefaults.set(showSubtrees, forKey: Self.showSubtreesKey)
        }
    }
    @Published var syncEnabled: Bool {
        didSet {
            userDefaults.set(syncEnabled, forKey: Self.settingsSyncEnabledKey)
        }
    }
    @Published var searchFilter: SearchFilter {
        didSet {
            userDefaults.set(searchFilter.rawValue, forKey: Self.searchFilterKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        showToolbarButtonText = userDefaults.object(forKey: Self.showToolbarButtonTextKey) as? Bool ?? true
        showSubmodules = userDefaults.object(forKey: Self.showSubmodulesKey) as? Bool ?? false
        showSubtrees = userDefaults.object(forKey: Self.showSubtreesKey) as? Bool ?? false
        syncEnabled = userDefaults.object(forKey: Self.settingsSyncEnabledKey) as? Bool ?? false
        searchFilter = userDefaults.string(forKey: Self.searchFilterKey)
            .flatMap(SearchFilter.init(rawValue:)) ?? .all
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            showToolbarButtonText: showToolbarButtonText,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees
        )
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        showToolbarButtonText = snapshot.showToolbarButtonText
        showSubmodules = snapshot.showSubmodules
        showSubtrees = snapshot.showSubtrees
    }
}
