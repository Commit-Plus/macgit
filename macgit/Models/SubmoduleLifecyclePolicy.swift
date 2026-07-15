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

enum SubmoduleLifecycleAction: Equatable {
    case editSettings
    case deinitialize(force: Bool)
    case remove(force: Bool)
}

struct SubmoduleLifecycleDecision: Equatable {
    let isAllowed: Bool
    let requiresConfirmation: Bool
    let message: String?
}

enum SubmoduleLifecyclePolicy {
    static func decision(
        for action: SubmoduleLifecycleAction,
        entry: GitSubmoduleEntry
    ) -> SubmoduleLifecycleDecision {
        switch action {
        case .editSettings:
            return SubmoduleLifecycleDecision(
                isAllowed: true,
                requiresConfirmation: false,
                message: nil
            )

        case .deinitialize(let force):
            guard entry.isInitialized else {
                return SubmoduleLifecycleDecision(
                    isAllowed: false,
                    requiresConfirmation: false,
                    message: "This submodule has no local checkout to deinitialize."
                )
            }
            return destructiveDecision(
                force: force,
                isDirty: isDirty(entry),
                confirmationMessage: "Deinitialize removes local checkout files. The .gitmodules entry and recorded gitlink remain."
            )

        case .remove(let force):
            return destructiveDecision(
                force: force,
                isDirty: isDirty(entry),
                confirmationMessage: "Remove Submodule stages the path and .gitmodules entry for removal."
            )
        }
    }

    private static func destructiveDecision(
        force: Bool,
        isDirty: Bool,
        confirmationMessage: String
    ) -> SubmoduleLifecycleDecision {
        guard !isDirty || force else {
            return SubmoduleLifecycleDecision(
                isAllowed: false,
                requiresConfirmation: true,
                message: "This submodule has uncommitted changes. Confirm force to continue."
            )
        }

        return SubmoduleLifecycleDecision(
            isAllowed: true,
            requiresConfirmation: true,
            message: confirmationMessage
        )
    }

    private static func isDirty(_ entry: GitSubmoduleEntry) -> Bool {
        switch entry.state {
        case .modified, .newCommits, .conflict:
            true
        case .clean, .uninitialized, .missing:
            false
        }
    }
}
