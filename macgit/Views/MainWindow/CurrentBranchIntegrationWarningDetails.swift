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

struct CurrentBranchIntegrationWarningDetails: View {
    let status: CurrentBranchIntegrationStatus
    let canUpdate: Bool
    let onUpdate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                status.predictsBaseConflict ? "Potential conflicts detected" : "Update available",
                systemImage: status.predictsBaseConflict
                    ? "exclamationmark.triangle.fill"
                    : "arrow.triangle.merge"
            )
            .bold()
            .foregroundStyle(status.predictsBaseConflict ? Color.red : .primary)

            if let upstreamRef = status.upstreamRef, status.upstreamBehindCount > 0 {
                Text(upstreamRef).bold()
                    + Text(" has \(status.upstreamBehindCount) new \(commitLabel(status.upstreamBehindCount)).")
            }
            if let baseRef = status.baseRef, status.baseBehindCount > 0 {
                Text(baseRef).bold()
                    + Text(" has \(status.baseBehindCount) \(commitLabel(status.baseBehindCount)) not in ")
                    + Text(status.branch).bold()
                    + Text(".")
            }
            if status.predictsBaseConflict {
                Text("Git predicts textual conflicts while merging the base branch.")
                    .foregroundStyle(.secondary)
            }

            Button("Update Current Branch", systemImage: "arrow.triangle.2.circlepath", action: onUpdate)
                .buttonStyle(.borderedProminent)
                .disabled(!canUpdate)

            if !canUpdate {
                Text("Commit or stash changes and finish other Git operations first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private func commitLabel(_ count: Int) -> String {
        count == 1 ? "commit" : "commits"
    }
}
