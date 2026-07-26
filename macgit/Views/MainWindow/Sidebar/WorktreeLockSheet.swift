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

struct WorktreeLockSheet: View {
    let entry: WorktreeEntry
    @Binding var reason: String
    let isUpdating: Bool
    let onCancel: () -> Void
    let onLock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lock Worktree")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                Text("Worktree:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(entry.path.path)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason (optional):")
                    .font(.system(size: 13))
                TextField("Reason", text: $reason)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isUpdating)

                Button("Lock", action: onLock)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isUpdating)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 480)
    }
}
