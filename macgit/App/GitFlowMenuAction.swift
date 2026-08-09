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

enum GitFlowMenuAction: Hashable {
    case start(GitFlowTopicKind)
    case finish(GitFlowTopicKind)
    case resumeFinish
    case abortFinish
    case configure
    case disable
}

struct GitFlowCommandState: Equatable {
    let isEnabled: Bool
    let currentKind: GitFlowTopicKind?
    let operationInProgress: Bool
    let hasPendingFinish: Bool
    let hasInvalidRecoveryState: Bool

    func canStart(_ kind: GitFlowTopicKind) -> Bool {
        isEnabled && !operationInProgress && !hasPendingFinish && !hasInvalidRecoveryState
    }

    func canFinish(_ kind: GitFlowTopicKind) -> Bool {
        isEnabled
            && !operationInProgress
            && !hasPendingFinish
            && !hasInvalidRecoveryState
            && kind.supportsFinish
            && currentKind == kind
    }

    var canResumeOrAbortFinish: Bool {
        isEnabled && !operationInProgress && hasPendingFinish
    }

    var canConfigure: Bool {
        !operationInProgress
    }
}

extension Notification.Name {
    static let gitFlowMenuAction = Notification.Name("macgit.gitFlowMenuAction")
}

struct GitFlowCommandStateKey: FocusedValueKey {
    typealias Value = GitFlowCommandState
}

extension FocusedValues {
    var gitFlowCommandState: GitFlowCommandState? {
        get { self[GitFlowCommandStateKey.self] }
        set { self[GitFlowCommandStateKey.self] = newValue }
    }
}
