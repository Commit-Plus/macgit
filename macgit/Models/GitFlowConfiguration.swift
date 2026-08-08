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

struct GitFlowConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var mainBranch: String
    var developBranch: String
    var featurePrefix: String
    var bugfixPrefix: String
    var releasePrefix: String
    var hotfixPrefix: String

    init(
        isEnabled: Bool = false,
        mainBranch: String = "main",
        developBranch: String = "develop",
        featurePrefix: String = "feature/",
        bugfixPrefix: String = "bugfix/",
        releasePrefix: String = "release/",
        hotfixPrefix: String = "hotfix/"
    ) {
        self.isEnabled = isEnabled
        self.mainBranch = mainBranch
        self.developBranch = developBranch
        self.featurePrefix = featurePrefix
        self.bugfixPrefix = bugfixPrefix
        self.releasePrefix = releasePrefix
        self.hotfixPrefix = hotfixPrefix
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        mainBranch = try container.decodeIfPresent(String.self, forKey: .mainBranch) ?? "main"
        developBranch = try container.decodeIfPresent(String.self, forKey: .developBranch) ?? "develop"
        featurePrefix = try container.decodeIfPresent(String.self, forKey: .featurePrefix) ?? "feature/"
        bugfixPrefix = try container.decodeIfPresent(String.self, forKey: .bugfixPrefix) ?? "bugfix/"
        releasePrefix = try container.decodeIfPresent(String.self, forKey: .releasePrefix) ?? "release/"
        hotfixPrefix = try container.decodeIfPresent(String.self, forKey: .hotfixPrefix) ?? "hotfix/"
    }

    static func detected(branches: [String]) -> GitFlowConfiguration {
        GitFlowConfiguration(
            mainBranch: branches.contains("main") ? "main" : (branches.contains("master") ? "master" : branches.first ?? "main"),
            developBranch: branches.contains("develop") ? "develop" : "develop"
        )
    }

    func prefix(for kind: GitFlowTopicKind) -> String {
        switch kind {
        case .feature: return featurePrefix
        case .bugfix: return bugfixPrefix
        case .release: return releasePrefix
        case .hotfix: return hotfixPrefix
        }
    }

    func baseBranch(for kind: GitFlowTopicKind) -> String {
        switch kind {
        case .feature, .bugfix, .release:
            return developBranch
        case .hotfix:
            return mainBranch
        }
    }

    func normalized() -> GitFlowConfiguration {
        GitFlowConfiguration(
            isEnabled: isEnabled,
            mainBranch: mainBranch.trimmingCharacters(in: .whitespacesAndNewlines),
            developBranch: developBranch.trimmingCharacters(in: .whitespacesAndNewlines),
            featurePrefix: Self.normalizedPrefix(featurePrefix),
            bugfixPrefix: Self.normalizedPrefix(bugfixPrefix),
            releasePrefix: Self.normalizedPrefix(releasePrefix),
            hotfixPrefix: Self.normalizedPrefix(hotfixPrefix)
        )
    }

    private static func normalizedPrefix(_ prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasSuffix("/") ? trimmed : "\(trimmed)/"
    }
}
