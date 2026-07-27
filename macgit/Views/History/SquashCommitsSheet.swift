//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
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

struct SquashCommitsSheet: View {
    let commits: [Commit]
    let initialMessage: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var message: String

    init(
        commits: [Commit],
        initialMessage: String,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String) -> Void
    ) {
        self.commits = commits
        self.initialMessage = initialMessage
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _message = State(initialValue: initialMessage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Squash Commits")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This is a combination of \(commits.count) commits.")
                .font(.system(size: 13))

            Text("Commit message")
                .font(.system(size: 13, weight: .medium))

            TextEditor(text: $message)
                .font(.system(size: 13))
                .frame(minHeight: 120)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Squash Commits") {
                    onConfirm(message)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 260)
    }
}
