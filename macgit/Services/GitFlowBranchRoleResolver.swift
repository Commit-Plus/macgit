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

struct GitFlowBranchRoleResolver {
    func role(for branch: String, configuration: GitFlowConfiguration) -> GitFlowBranchRole? {
        let configuration = configuration.normalized()
        guard configuration.isEnabled else { return nil }
        if branch == configuration.mainBranch { return .main }
        if branch == configuration.developBranch { return .develop }

        let matches = GitFlowTopicKind.allCases.compactMap { kind -> (GitFlowTopicKind, String)? in
            let prefix = configuration.prefix(for: kind)
            guard !prefix.isEmpty, branch.hasPrefix(prefix), branch.count > prefix.count else { return nil }
            return (kind, prefix)
        }
        guard let match = matches.sorted(by: { lhs, rhs in
            if lhs.1.count != rhs.1.count { return lhs.1.count > rhs.1.count }
            return lhs.0.rawValue < rhs.0.rawValue
        }).first else { return nil }

        switch match.0 {
        case .feature: return .feature
        case .bugfix: return .bugfix
        case .release: return .release
        case .hotfix: return .hotfix
        }
    }
}
