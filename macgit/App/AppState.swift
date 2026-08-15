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

final class AppState: ObservableObject {
    static let shared = AppState()
    private static let appearanceKey = "appearance"
    private static let showToolbarButtonTextKey = "showToolbarButtonText"
    private static let showGitFlowKey = "showGitFlow"
    private static let showSubmodulesKey = "showSubmodules"
    private static let showSubtreesKey = "showSubtrees"
    private static let showHeaderBranchButtonKey = "showHeaderBranchButton"
    private static let showHeaderMergeButtonKey = "showHeaderMergeButton"
    private static let showHeaderStashButtonKey = "showHeaderStashButton"
    private static let showHeaderRemoteButtonKey = "showHeaderRemoteButton"
    private static let showHeaderFinderButtonKey = "showHeaderFinderButton"
    private static let showHeaderEditorButtonKey = "showHeaderEditorButton"
    private static let showHeaderTerminalButtonKey = "showHeaderTerminalButton"
    private static let historyBranchFilterKey = "historyBranchFilter"
    private static let historyIncludeRemotesKey = "historyIncludeRemotes"
    private static let autoFetchEnabledKey = "autoFetchEnabled"
    private static let refreshOnAppActiveKey = "refreshOnAppActive"
    private static let settingsSyncEnabledKey = "settingsSyncEnabled"
    private static let searchFilterKey = "searchFilter"
    private static let preferredSearchFileApplicationKey = "preferredSearchFileApplication"

    private let userDefaults: UserDefaults
    private var isApplyingSnapshot = false
    @Published private var currentSettingsSnapshot: AppSettingsSnapshot =
        AppSettingsSnapshot(showToolbarButtonText: true, showSubmodules: false, showSubtrees: false)

    @Published var appearance: AppAppearance {
        didSet {
            userDefaults.set(appearance.rawValue, forKey: Self.appearanceKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showToolbarButtonText: Bool {
        didSet {
            userDefaults.set(showToolbarButtonText, forKey: Self.showToolbarButtonTextKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showGitFlow: Bool {
        didSet {
            userDefaults.set(showGitFlow, forKey: Self.showGitFlowKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showSubmodules: Bool {
        didSet {
            userDefaults.set(showSubmodules, forKey: Self.showSubmodulesKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showSubtrees: Bool {
        didSet {
            userDefaults.set(showSubtrees, forKey: Self.showSubtreesKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderBranchButton: Bool {
        didSet {
            userDefaults.set(showHeaderBranchButton, forKey: Self.showHeaderBranchButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderMergeButton: Bool {
        didSet {
            userDefaults.set(showHeaderMergeButton, forKey: Self.showHeaderMergeButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderStashButton: Bool {
        didSet {
            userDefaults.set(showHeaderStashButton, forKey: Self.showHeaderStashButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderRemoteButton: Bool {
        didSet {
            userDefaults.set(showHeaderRemoteButton, forKey: Self.showHeaderRemoteButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderFinderButton: Bool {
        didSet {
            userDefaults.set(showHeaderFinderButton, forKey: Self.showHeaderFinderButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderEditorButton: Bool {
        didSet {
            userDefaults.set(showHeaderEditorButton, forKey: Self.showHeaderEditorButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var showHeaderTerminalButton: Bool {
        didSet {
            userDefaults.set(showHeaderTerminalButton, forKey: Self.showHeaderTerminalButtonKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var historyBranchFilter: HistoryBranchFilter {
        didSet {
            userDefaults.set(historyBranchFilter.storageValue, forKey: Self.historyBranchFilterKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var historyIncludeRemotes: Bool {
        didSet {
            userDefaults.set(historyIncludeRemotes, forKey: Self.historyIncludeRemotesKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var autoFetchEnabled: Bool {
        didSet {
            userDefaults.set(autoFetchEnabled, forKey: Self.autoFetchEnabledKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
        }
    }
    @Published var refreshOnAppActive: Bool {
        didSet {
            userDefaults.set(refreshOnAppActive, forKey: Self.refreshOnAppActiveKey)
            if !isApplyingSnapshot {
                currentSettingsSnapshot = snapshot
            }
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
        $currentSettingsSnapshot
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let appearance = userDefaults.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        let showToolbarButtonText = userDefaults.object(forKey: Self.showToolbarButtonTextKey) as? Bool ?? true
        let showGitFlow = userDefaults.object(forKey: Self.showGitFlowKey) as? Bool ?? true
        let showSubmodules = userDefaults.object(forKey: Self.showSubmodulesKey) as? Bool ?? false
        let showSubtrees = userDefaults.object(forKey: Self.showSubtreesKey) as? Bool ?? false
        let showHeaderBranchButton = userDefaults.object(forKey: Self.showHeaderBranchButtonKey) as? Bool ?? true
        let showHeaderMergeButton = userDefaults.object(forKey: Self.showHeaderMergeButtonKey) as? Bool ?? true
        let showHeaderStashButton = userDefaults.object(forKey: Self.showHeaderStashButtonKey) as? Bool ?? true
        let showHeaderRemoteButton = userDefaults.object(forKey: Self.showHeaderRemoteButtonKey) as? Bool ?? true
        let showHeaderFinderButton = userDefaults.object(forKey: Self.showHeaderFinderButtonKey) as? Bool ?? true
        let showHeaderEditorButton = userDefaults.object(forKey: Self.showHeaderEditorButtonKey) as? Bool ?? true
        let showHeaderTerminalButton = userDefaults.object(forKey: Self.showHeaderTerminalButtonKey) as? Bool ?? true
        let historyBranchFilter = userDefaults.string(forKey: Self.historyBranchFilterKey)
            .flatMap(HistoryBranchFilter.init(storageValue:)) ?? .all
        let historyIncludeRemotes = userDefaults.object(forKey: Self.historyIncludeRemotesKey) as? Bool ?? false
        let autoFetchEnabled = userDefaults.object(forKey: Self.autoFetchEnabledKey) as? Bool ?? false
        let refreshOnAppActive = userDefaults.object(forKey: Self.refreshOnAppActiveKey) as? Bool ?? true
        let syncEnabled = userDefaults.object(forKey: Self.settingsSyncEnabledKey) as? Bool ?? false
        let searchFilter = userDefaults.string(forKey: Self.searchFilterKey)
            .flatMap(SearchFilter.init(rawValue:)) ?? .all
        let preferredSearchFileApplicationBundleIdentifier = userDefaults.string(
            forKey: Self.preferredSearchFileApplicationKey
        )

        self.appearance = appearance
        self.showToolbarButtonText = showToolbarButtonText
        self.showGitFlow = showGitFlow
        self.showSubmodules = showSubmodules
        self.showSubtrees = showSubtrees
        self.showHeaderBranchButton = showHeaderBranchButton
        self.showHeaderMergeButton = showHeaderMergeButton
        self.showHeaderStashButton = showHeaderStashButton
        self.showHeaderRemoteButton = showHeaderRemoteButton
        self.showHeaderFinderButton = showHeaderFinderButton
        self.showHeaderEditorButton = showHeaderEditorButton
        self.showHeaderTerminalButton = showHeaderTerminalButton
        self.historyBranchFilter = historyBranchFilter
        self.historyIncludeRemotes = historyIncludeRemotes
        self.autoFetchEnabled = autoFetchEnabled
        self.refreshOnAppActive = refreshOnAppActive
        self.syncEnabled = syncEnabled
        self.searchFilter = searchFilter
        self.preferredSearchFileApplicationBundleIdentifier = preferredSearchFileApplicationBundleIdentifier
        currentSettingsSnapshot = AppSettingsSnapshot(
            appearance: appearance,
            showToolbarButtonText: showToolbarButtonText,
            showGitFlow: showGitFlow,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees,
            showHeaderBranchButton: showHeaderBranchButton,
            showHeaderMergeButton: showHeaderMergeButton,
            showHeaderStashButton: showHeaderStashButton,
            showHeaderRemoteButton: showHeaderRemoteButton,
            showHeaderFinderButton: showHeaderFinderButton,
            showHeaderEditorButton: showHeaderEditorButton,
            showHeaderTerminalButton: showHeaderTerminalButton,
            historyBranchFilter: historyBranchFilter,
            historyIncludeRemotes: historyIncludeRemotes,
            autoFetchEnabled: autoFetchEnabled,
            refreshOnAppActive: refreshOnAppActive
        )
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            appearance: appearance,
            showToolbarButtonText: showToolbarButtonText,
            showGitFlow: showGitFlow,
            showSubmodules: showSubmodules,
            showSubtrees: showSubtrees,
            showHeaderBranchButton: showHeaderBranchButton,
            showHeaderMergeButton: showHeaderMergeButton,
            showHeaderStashButton: showHeaderStashButton,
            showHeaderRemoteButton: showHeaderRemoteButton,
            showHeaderFinderButton: showHeaderFinderButton,
            showHeaderEditorButton: showHeaderEditorButton,
            showHeaderTerminalButton: showHeaderTerminalButton,
            historyBranchFilter: historyBranchFilter,
            historyIncludeRemotes: historyIncludeRemotes,
            autoFetchEnabled: autoFetchEnabled,
            refreshOnAppActive: refreshOnAppActive
        )
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        isApplyingSnapshot = true
        defer { isApplyingSnapshot = false }
        appearance = snapshot.appearance
        showToolbarButtonText = snapshot.showToolbarButtonText
        showGitFlow = snapshot.showGitFlow
        showSubmodules = snapshot.showSubmodules
        showSubtrees = snapshot.showSubtrees
        showHeaderBranchButton = snapshot.showHeaderBranchButton
        showHeaderMergeButton = snapshot.showHeaderMergeButton
        showHeaderStashButton = snapshot.showHeaderStashButton
        showHeaderRemoteButton = snapshot.showHeaderRemoteButton
        showHeaderFinderButton = snapshot.showHeaderFinderButton
        showHeaderEditorButton = snapshot.showHeaderEditorButton
        showHeaderTerminalButton = snapshot.showHeaderTerminalButton
        historyBranchFilter = snapshot.historyBranchFilter
        historyIncludeRemotes = snapshot.historyIncludeRemotes
        autoFetchEnabled = snapshot.autoFetchEnabled
        refreshOnAppActive = snapshot.refreshOnAppActive
        currentSettingsSnapshot = snapshot
    }

    func restoreLocalOnlyPreferences() {
        searchFilter = .all
        preferredSearchFileApplicationBundleIdentifier = nil
    }
}
