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

struct GitFlowFinishPlan: Identifiable, Codable, Equatable {
    let kind: GitFlowTopicKind
    let sourceBranch: String
    let primaryTargetBranch: String
    let secondaryTargetBranch: String?
    var tagName: String?
    var createTag: Bool
    var deleteSourceBranch: Bool

    var id: String { "\(kind.rawValue):\(sourceBranch)" }

    var targetBranch: String { primaryTargetBranch }

    var targetBranches: [String] {
        if let secondaryTargetBranch {
            return [primaryTargetBranch, secondaryTargetBranch]
        }
        return [primaryTargetBranch]
    }

    init(
        kind: GitFlowTopicKind,
        sourceBranch: String,
        targetBranch: String,
        secondaryTargetBranch: String? = nil,
        tagName: String? = nil,
        createTag: Bool = false,
        deleteSourceBranch: Bool
    ) {
        self.kind = kind
        self.sourceBranch = sourceBranch
        self.primaryTargetBranch = targetBranch
        self.secondaryTargetBranch = secondaryTargetBranch
        self.tagName = tagName
        self.createTag = createTag
        self.deleteSourceBranch = deleteSourceBranch
    }
}

struct GitFlowFinishResult: Equatable {
    let plan: GitFlowFinishPlan
    let sourceTip: String
    let targetResults: [GitFlowFinishTargetResult]
    let createdTagName: String?
    let didDeleteSourceBranch: Bool
    let deletionWarning: String?

    var targetTipBeforeMerge: String {
        targetResults.first?.tipBeforeMerge ?? ""
    }

    var targetTipAfterMerge: String {
        targetResults.first?.tipAfterMerge ?? ""
    }
}

struct GitFlowFinishTargetResult: Codable, Equatable {
    let branch: String
    let tipBeforeMerge: String
    let tipAfterMerge: String
}
