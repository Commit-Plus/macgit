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
    private static let showHeaderBranchButtonKey = "showHeaderBranchButton"
    private static let showHeaderMergeButtonKey = "showHeaderMergeButton"
    private static let showHeaderStashButtonKey = "showHeaderStashButton"
    private static let showHeaderRemoteButtonKey = "showHeaderRemoteButton"
    private static let showHeaderFinderButtonKey = "showHeaderFinderButton"
    private static let showHeaderTerminalButtonKey = "showHeaderTerminalButton"
    private static let settingsSyncEnabledKey = "settingsSyncEnabled"
    private static let searchFilterKey = "searchFilter"
    private static let preferredSearchFileApplicationKey = "preferredSearchFileApplication"

    private let userDefaults: UserDefaults

    @Published var fileMenuAction: FileMenuAction?
    @Published var openWindowWithCloneSheet = false
    @Published var newWindowRepoURL: URL?
    @Published var hasOpenRepository = false
    @Published var showToolbarButtonText: Bool {
        didSet { userDefaults.set(showToolbarButtonText, forKey: Self.showToolbarButtonTextKey) }
    }
    @Published var showSubmodules: Bool {
        didSet { userDefaults.set(showSubmodules, forKey: Self.showSubmodulesKey) }
    }
    @Published var showSubtrees: Bool {
        didSet { userDefaults.set(showSubtrees, forKey: Self.showSubtreesKey) }
    }
    @Published var showHeaderBranchButton: Bool {
        didSet { userDefaults.set(showHeaderBranchButton, forKey: Self.showHeaderBranchButtonKey) }
    }
    @Published var showHeaderMergeButton: Bool {
        didSet { userDefaults.set(showHeaderMergeButton, forKey: Self.showHeaderMergeButtonKey) }
    }
    @Published var showHeaderStashButton: Bool {
        didSet { userDefaults.set(showHeaderStashButton, forKey: Self.showHeaderStashButtonKey) }
    }
    @Published var showHeaderRemoteButton: Bool {
        didSet { userDefaults.set(showHeaderRemoteButton, forKey: Self.showHeaderRemoteButtonKey) }
    }
    @Published var showHeaderFinderButton: Bool {
        didSet { userDefaults.set(showHeaderFinderButton, forKey: Self.showHeaderFinderButtonKey) }
    }
    @Published var showHeaderTerminalButton: Bool {
        didSet { userDefaults.set(showHeaderTerminalButton, forKey: Self.showHeaderTerminalButtonKey) }
    }
    @Published var syncEnabled: Bool {
        didSet { userDefaults.set(syncEnabled, forKey: Self.settingsSyncEnabledKey) }
    }
    @Published var searchFilter: SearchFilter {
        didSet { userDefaults.set(searchFilter.rawValue, forKey: Self.searchFilterKey) }
    }
    @Published var preferredSearchFileApplicationBundleIdentifier: String? {
        didSet {
            if let preferredSearchFileApplicationBundleIdentifier {
                userDefaults.set(
                    preferredSearchFileApplicationBundleIdentifier,
                    forKey: Self.preferredSearchFileApplicationKey
                )
            } else {
                userDefaults.removeObject(forKey: Self.preferredSearchFileApplicationKey)
            }
        }
    }

    var settingsSnapshotPublisher: AnyPublisher<AppSettingsSnapshot, Never> {
        let publishers: [AnyPublisher<AppSettingsSnapshot, Never>] = [
            $showToolbarButtonText.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher(),
            $showSubmodules.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher(),
            $showSubtrees.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher(),
            $showHeaderBranchButton.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher(),
            $showHeaderMergeButton.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher(),
            $showHeaderStashButton.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher(),
            $showHeaderRemoteButton.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher(),
            $showHeaderFinderButton.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher(),
            $showHeaderTerminalButton.map { [weak self] _ in self?.snapshot ?? AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false) }.eraseToAnyPublisher()
        ]
        return Publishers.MergeMany(publishers)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        showToolbarButtonText = userDefaults.object(forKey: Self.showToolbarButtonTextKey) as? Bool ?? true
        showSubmodules = userDefaults.object(forKey: Self.showSubmodulesKey) as? Bool ?? false
        showSubtrees = userDefaults.object(forKey: Self.showSubtreesKey) as? Bool ?? false
        showHeaderBranchButton = userDefaults.object(forKey: Self.showHeaderBranchButtonKey) as? Bool ?? true
        showHeaderMergeButton = userDefaults.object(forKey: Self.showHeaderMergeButtonKey) as? Bool ?? true
        showHeaderStashButton = userDefaults.object(forKey: Self.showHeaderStashButtonKey) as? Bool ?? true
        showHeaderRemoteButton = userDefaults.object(forKey: Self.showHeaderRemoteButtonKey) as? Bool ?? true
        showHeaderFinderButton = userDefaults.object(forKey: Self.showHeaderFinderButtonKey) as? Bool ?? true
        showHeaderTerminalButton = userDefaults.object(forKey: Self.showHeaderTerminalButtonKey) as? Bool ?? true
        syncEnabled = userDefaults.object(forKey: Self.settingsSyncEnabledKey) as? Bool ?? false
        searchFilter = userDefaults.string(forKey: Self.searchFilterKey)
            .flatMap(SearchFilter.init(rawValue:)) ?? .all
        preferredSearchFileApplicationBundleIdentifier = userDefaults.string(
            forKey: Self.preferredSearchFileApplicationKey
        )
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            showToolbarButtonText: showToolbarButtonText,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees,
            showHeaderBranchButton: showHeaderBranchButton,
            showHeaderMergeButton: showHeaderMergeButton,
            showHeaderStashButton: showHeaderStashButton,
            showHeaderRemoteButton: showHeaderRemoteButton,
            showHeaderFinderButton: showHeaderFinderButton,
            showHeaderTerminalButton: showHeaderTerminalButton
        )
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        showToolbarButtonText = snapshot.showToolbarButtonText
        showSubmodules = snapshot.showSubmodules
        showSubtrees = snapshot.showSubtrees
        showHeaderBranchButton = snapshot.showHeaderBranchButton
        showHeaderMergeButton = snapshot.showHeaderMergeButton
        showHeaderStashButton = snapshot.showHeaderStashButton
        showHeaderRemoteButton = snapshot.showHeaderRemoteButton
        showHeaderFinderButton = snapshot.showHeaderFinderButton
        showHeaderTerminalButton = snapshot.showHeaderTerminalButton
    }
}
