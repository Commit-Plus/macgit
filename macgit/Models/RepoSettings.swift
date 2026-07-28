//
//  RepoSettings.swift
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

enum PullStrategy: String, Codable, CaseIterable {
    case merge
    case rebase
}

struct RepoSettings: Codable, Equatable {
    var defaultRemoteName: String?
    var defaultPullBranch: String
    var pullStrategy: PullStrategy
    var autoFetchEnabled: Bool
    var refreshOnAppActive: Bool
    var confirmDetachedHeadCheckout: Bool
    var confirmDestructiveStashActions: Bool
    var useGlobalUserSettings: Bool
    var userName: String
    var userEmail: String

    init(
        defaultRemoteName: String? = nil,
        defaultPullBranch: String,
        pullStrategy: PullStrategy = .merge,
        autoFetchEnabled: Bool = false,
        refreshOnAppActive: Bool = true,
        confirmDetachedHeadCheckout: Bool = true,
        confirmDestructiveStashActions: Bool = true,
        useGlobalUserSettings: Bool = true,
        userName: String = "",
        userEmail: String = ""
    ) {
        self.defaultRemoteName = defaultRemoteName
        self.defaultPullBranch = defaultPullBranch
        self.pullStrategy = pullStrategy
        self.autoFetchEnabled = autoFetchEnabled
        self.refreshOnAppActive = refreshOnAppActive
        self.confirmDetachedHeadCheckout = confirmDetachedHeadCheckout
        self.confirmDestructiveStashActions = confirmDestructiveStashActions
        self.useGlobalUserSettings = useGlobalUserSettings
        self.userName = userName
        self.userEmail = userEmail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultRemoteName = try container.decodeIfPresent(String.self, forKey: .defaultRemoteName)
        defaultPullBranch = try container.decodeIfPresent(String.self, forKey: .defaultPullBranch) ?? ""
        pullStrategy = try container.decodeIfPresent(PullStrategy.self, forKey: .pullStrategy) ?? .merge
        autoFetchEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoFetchEnabled) ?? false
        refreshOnAppActive = try container.decodeIfPresent(Bool.self, forKey: .refreshOnAppActive) ?? true
        confirmDetachedHeadCheckout = try container.decodeIfPresent(Bool.self, forKey: .confirmDetachedHeadCheckout) ?? true
        confirmDestructiveStashActions = try container.decodeIfPresent(Bool.self, forKey: .confirmDestructiveStashActions) ?? true
        useGlobalUserSettings = try container.decodeIfPresent(Bool.self, forKey: .useGlobalUserSettings) ?? true
        userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? ""
        userEmail = try container.decodeIfPresent(String.self, forKey: .userEmail) ?? ""
    }

    static func defaults(currentBranch: String?, remotes: [String]) -> RepoSettings {
        RepoSettings(
            defaultRemoteName: remotes.first,
            defaultPullBranch: currentBranch ?? ""
        )
    }
}
