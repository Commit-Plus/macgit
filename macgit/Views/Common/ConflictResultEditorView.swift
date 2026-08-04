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

struct ConflictResultEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let onTextChange: (String) -> Void
    let fileExtension: String
    let baselineText: String
    let isDisabled: Bool
    let undoResetGeneration: Int
    let scrollController: SyncedScrollController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Result")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Label("Editable", systemImage: "pencil")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.secondary.opacity(0.04))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator.opacity(0.5))
                    .frame(height: 0.5)
            }

            ConflictResultTextView(
                text: text,
                onTextChange: onTextChange,
                fileExtension: fileExtension,
                baselineText: baselineText,
                colorScheme: colorScheme,
                isEditable: !isDisabled,
                undoResetGeneration: undoResetGeneration,
                scrollID: "result",
                scrollController: scrollController
            )
                .accessibilityLabel("Merge result")
        }
    }
}
