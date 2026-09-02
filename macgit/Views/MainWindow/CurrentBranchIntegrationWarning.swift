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

struct CurrentBranchIntegrationWarning: View {
    let status: CurrentBranchIntegrationStatus
    let canUpdate: Bool
    let onUpdate: () -> Void

    @State private var showingDetails = false

    var body: some View {
        Button("Show Current Branch Update", systemImage: warningSymbol, action: showDetails)
            .labelStyle(.iconOnly)
            .foregroundStyle(status.predictsBaseConflict ? Color.red : Color.orange)
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .help(helpText)
            .accessibilityHint(helpText)
            .onContinuousHover(perform: updateCursor)
            .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
                CurrentBranchIntegrationWarningDetails(
                    status: status,
                    canUpdate: canUpdate,
                    onUpdate: performUpdate
                )
            }
    }

    private var warningSymbol: String {
        status.predictsBaseConflict
            ? "exclamationmark.triangle.fill"
            : "exclamationmark.triangle"
    }

    private var helpText: String {
        if status.predictsBaseConflict {
            "The current branch needs an update and may conflict with \(status.baseRef ?? "its base branch")."
        } else {
            "The current branch has remote or base-branch updates available."
        }
    }

    private func showDetails() {
        showingDetails.toggle()
    }

    private func updateCursor(_ phase: HoverPhase) {
        switch phase {
        case .active:
            NSCursor.pointingHand.set()
        case .ended:
            NSCursor.arrow.set()
        }
    }

    private func performUpdate() {
        showingDetails = false
        onUpdate()
    }
}
