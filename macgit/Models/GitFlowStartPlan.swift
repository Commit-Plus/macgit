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

final class GitFlowStartPlan: Equatable, Sendable {
    let kind: GitFlowTopicKind
    let branchName: String
    let baseBranch: String
    let destination: GitFlowStartDestination
    let worktreePath: URL?
    let worktreeLabel: String?

    init(
        kind: GitFlowTopicKind,
        branchName: String,
        baseBranch: String,
        destination: GitFlowStartDestination = .currentWorkingCopy,
        worktreePath: URL? = nil,
        worktreeLabel: String? = nil
    ) {
        self.kind = kind
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.destination = destination
        self.worktreePath = worktreePath
        self.worktreeLabel = worktreeLabel
    }

    static func == (lhs: GitFlowStartPlan, rhs: GitFlowStartPlan) -> Bool {
        lhs.kind == rhs.kind
            && lhs.branchName == rhs.branchName
            && lhs.baseBranch == rhs.baseBranch
            && lhs.destination == rhs.destination
            && lhs.worktreePath == rhs.worktreePath
            && lhs.worktreeLabel == rhs.worktreeLabel
    }
}

enum GitFlowStartPlacement: Equatable {
    case currentWorkingCopy(previousRef: String)
    case newWorktree(path: URL, label: String?)
}

struct GitFlowStartResult: Equatable {
    let plan: GitFlowStartPlan
    let placement: GitFlowStartPlacement
    let baseTip: String
    let createdTip: String
}
