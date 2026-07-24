//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

extension MainWindowView {
    func performSubtreeOperation(_ pending: PendingSubtreeOperation) async throws {
        let decision = try await GitStatusService.shared.subtreeOperationDecision(in: repositoryURL)
        guard decision.isAllowed else {
            throw GitError.commandFailed(subtreeBlockedMessage(for: decision))
        }

        switch pending.operation {
        case .add:
            return
        case .pull:
            try await GitStatusService.shared.pullSubtree(
                pending.entry,
                in: repositoryURL,
                credentialResolver: providerAccountController.credentialResolver()
            )
        case .push:
            try await GitStatusService.shared.pushSubtree(
                pending.entry,
                in: repositoryURL,
                credentialResolver: providerAccountController.credentialResolver()
            )
        }
    }

    func subtreeBlockedMessage(for decision: SubtreeOperationDecision) -> String {
        guard !decision.blockingPaths.isEmpty else {
            return decision.message ?? SubtreeOperationPolicy.dirtyTreeMessage
        }

        let shownPaths = decision.blockingPaths.prefix(5).map { "- \($0)" }.joined(separator: "\n")
        let remaining = decision.blockingPaths.count - 5
        let suffix = remaining > 0 ? "\n+ \(remaining) more" : ""
        return "\(decision.message ?? SubtreeOperationPolicy.dirtyTreeMessage)\n\n\(shownPaths)\(suffix)"
    }
}
