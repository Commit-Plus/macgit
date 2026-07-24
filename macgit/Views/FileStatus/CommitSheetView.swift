//
//  CommitSheetView.swift
//  macgit
//

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

struct CommitSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("commit.allChanges") private var commitAllChanges = false
    @State private var message: String = ""
    let hasStagedChanges: Bool
    let onCommit: (String, Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Commit Changes")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit Message")
                    .font(.headline)
                Text("Leave this empty to create a commit without a message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Enter a commit message…", text: $message, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 400)
                    .lineLimit(3...6)
                if !hasStagedChanges {
                    HStack(spacing: 8) {
                        Label("No files staged", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Toggle("Commit all changes", isOn: $commitAllChanges)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12))
                    }
                    .frame(width: 400, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Commit Without Message" : "Commit") {
                    onCommit(message, !hasStagedChanges && commitAllChanges)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasStagedChanges && !commitAllChanges)
            }
        }
        .padding(30)
        .frame(minWidth: 480)
    }
}
