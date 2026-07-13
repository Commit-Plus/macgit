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

nonisolated struct TagDetailsPresentation: Equatable {
    let tagName: String
    let commitHash: String
    let author: String
    let date: String
    let message: String

    init(details: GitTagDetails) {
        tagName = details.name
        commitHash = details.commitHash
        author = "\(details.authorName) <\(details.authorEmail)>"
        date = details.date.formatted(date: .abbreviated, time: .standard)
        message = details.body.isEmpty
            ? details.subject
            : "\(details.subject)\n\n\(details.body)"
    }
}

struct TagDetailsSheet: View {
    let presentation: TagDetailsPresentation
    let onDismiss: () -> Void

    init(details: GitTagDetails, onDismiss: @escaping () -> Void) {
        presentation = TagDetailsPresentation(details: details)
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            Text("Tag details")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                detailRow(label: "Tag", value: presentation.tagName)
                detailRow(label: "Commit", value: presentation.commitHash)
                detailRow(label: "Author", value: presentation.author)
                detailRow(label: "Date", value: presentation.date)
            }
            .textSelection(.enabled)

            ScrollView {
                Text(presentation.message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 80, maxHeight: 180)

            Button(action: onDismiss) {
                Text("OK")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(minWidth: 420, idealWidth: 460)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .fontWeight(.semibold)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
