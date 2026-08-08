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

enum GitFlowPlannerError: LocalizedError, Equatable {
    case disabled
    case emptyTopicName
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "Git Flow is not enabled for this repository."
        case .emptyTopicName:
            return "Enter a name for the new branch."
        case .invalidConfiguration(let message):
            return message
        }
    }
}

struct GitFlowPlanner {
    func startPlan(
        kind: GitFlowTopicKind,
        topicName: String,
        configuration: GitFlowConfiguration
    ) throws -> GitFlowStartPlan {
        let configuration = configuration.normalized()
        guard configuration.isEnabled else { throw GitFlowPlannerError.disabled }
        try validate(configuration)

        let name = topicName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GitFlowPlannerError.emptyTopicName }

        return GitFlowStartPlan(
            kind: kind,
            branchName: configuration.prefix(for: kind) + name,
            baseBranch: configuration.baseBranch(for: kind)
        )
    }

    func topicKind(
        for branch: String,
        configuration: GitFlowConfiguration
    ) -> GitFlowTopicKind? {
        GitFlowTopicKind.allCases.first { kind in
            let prefix = configuration.normalized().prefix(for: kind)
            return !prefix.isEmpty && branch.hasPrefix(prefix) && branch.count > prefix.count
        }
    }

    func finishPlan(
        kind: GitFlowTopicKind,
        currentBranch: String,
        configuration: GitFlowConfiguration,
        deleteSourceBranch: Bool = true
    ) throws -> GitFlowFinishPlan {
        let configuration = configuration.normalized()
        guard configuration.isEnabled else { throw GitFlowPlannerError.disabled }
        try validate(configuration)
        guard kind.supportsPhaseTwoFinish else {
            throw GitFlowPlannerError.invalidConfiguration("Finish \(kind.displayName) is planned for a later Git Flow phase.")
        }
        guard topicKind(for: currentBranch, configuration: configuration) == kind else {
            throw GitFlowPlannerError.invalidConfiguration(
                "Check out a \(kind.displayName) branch before finishing it."
            )
        }

        return GitFlowFinishPlan(
            kind: kind,
            sourceBranch: currentBranch,
            targetBranch: configuration.developBranch,
            deleteSourceBranch: deleteSourceBranch
        )
    }

    func validate(_ configuration: GitFlowConfiguration) throws {
        let configuration = configuration.normalized()
        guard !configuration.mainBranch.isEmpty else {
            throw GitFlowPlannerError.invalidConfiguration("Select a Main branch.")
        }
        guard !configuration.developBranch.isEmpty else {
            throw GitFlowPlannerError.invalidConfiguration("Select a Develop branch.")
        }
        guard configuration.mainBranch != configuration.developBranch else {
            throw GitFlowPlannerError.invalidConfiguration("Main and Develop must be different branches.")
        }

        let prefixes = GitFlowTopicKind.allCases.map { configuration.prefix(for: $0) }
        guard prefixes.allSatisfy({ !$0.isEmpty }) else {
            throw GitFlowPlannerError.invalidConfiguration("Every Git Flow prefix must have a value.")
        }
        guard Set(prefixes).count == prefixes.count else {
            throw GitFlowPlannerError.invalidConfiguration("Git Flow prefixes must be unique.")
        }
    }
}
