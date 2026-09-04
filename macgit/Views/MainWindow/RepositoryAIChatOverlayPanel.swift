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

struct RepositoryAIChatOverlayPanel: View {
    private static let resizeHitAreaWidth: CGFloat = 12

    @Binding var width: CGFloat
    let onDismiss: () -> Void
    @ObservedObject var repositoryAIController: RepositoryAIChatController
    @ObservedObject var aiProviderController: AIProviderController
    let repositoryChatAccess: FeatureAccessDecision
    let isSignedIn: Bool
    let onRequestRepositoryChatAccess: () -> Void
    let onExecuteRemoteOperation: (RepositoryAIValidatedRemoteOperation) async throws -> RepositoryAIRemoteOperationExecutionResult

    var body: some View {
        ZStack(alignment: .leading) {
            RepositoryToolbarShortcutPanel(
                onDismiss: onDismiss,
                repositoryAIController: repositoryAIController,
                aiProviderController: aiProviderController,
                repositoryChatAccess: repositoryChatAccess,
                isSignedIn: isSignedIn,
                onRequestRepositoryChatAccess: onRequestRepositoryChatAccess,
                onExecuteRemoteOperation: onExecuteRemoteOperation
            )

            RepositoryAIChatResizeHandle(
                panelWidth: $width,
                minimumWidth: RepositoryToolbarShortcutPanel.minimumWidth,
                maximumWidth: RepositoryToolbarShortcutPanel.maximumWidth
            )
            .frame(width: Self.resizeHitAreaWidth)
            .frame(maxHeight: .infinity)
        }
        .frame(width: width)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}
