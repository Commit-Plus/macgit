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

struct SidebarDeletePrefixSheet: View {
    let prefix: String
    let allBranches: [String]
    let deletableBranches: [String]
    let skippedBranches: [String]
    @Binding var forceDelete: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete All Branches in \u{201C}\(prefix)/\u{201D}")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This will delete \(deletableBranches.count) branch\(deletableBranches.count == 1 ? "" : "es") with the prefix \u{201C}\(prefix)/\u{201D}.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            if let currentBranch = skippedBranches.first {
                Text("The current branch \u{201C}\(currentBranch)\u{201D} will be skipped because it is checked out.")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(deletableBranches, id: \.self) { branch in
                    Text("\u{2022} \(branch)")
                        .font(.system(size: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Force delete regardless of merge status", isOn: $forceDelete)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Text("Use \u{201C}git branch -D\u{201D}. Required for branches that are not fully merged; otherwise their commits may become unreachable.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(forceDelete ? "Force Delete All" : "Delete All", role: .destructive, action: onDelete)
                    .keyboardShortcut(.defaultAction)
                    .disabled(deletableBranches.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
    }
}
