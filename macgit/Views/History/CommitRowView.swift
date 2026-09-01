//
//  CommitRowView.swift
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

struct CommitRowView: View {
    let commit: Commit
    let graphWidth: CGFloat
    let isSelected: Bool
    let isDragActive: Bool
    let graphColorIndex: Int?
    let messageWidth: CGFloat
    let authorWidth: CGFloat
    let dateWidth: CGFloat
    let commitWidth: CGFloat
    let onDoubleClick: () -> Void

    private var authorText: String {
        "\(commit.author) <\(commit.email)>"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Fixed-width spacer so all commit messages align regardless of lane count
            Color.clear
                .frame(width: graphWidth, height: 24)
                .fixedSize()

            // Ref labels stay on one line at the start of the message column;
            // the commit message uses the remaining space and truncates at the end.
            HStack(spacing: 4) {
                if !commit.refs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(commit.refs.prefix(3), id: \.self) { ref in
                            RefLabel(text: ref, graphColorIndex: graphColorIndex)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                Text(commit.message)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: messageWidth, alignment: .leading)

            // Author
            Text(authorText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: authorWidth, alignment: .leading)

            // Date
            Text(
                commit.date,
                format: .dateTime
                    .hour()
                    .minute()
                    .day()
                    .month(.abbreviated)
                    .year()
            )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: dateWidth, alignment: .trailing)

            // Hash
            Text(commit.shortHash)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: commitWidth, alignment: .trailing)

            // Match the last resizer width in the header
            Color.clear
                .frame(width: 6, height: 24)
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .frame(height: 24)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .opacity(isDragActive ? 0.4 : 1)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onDoubleClick()
                }
        )
    }
}

struct RefLabel: View {
    let text: String
    let graphColorIndex: Int?

    init(text: String, graphColorIndex: Int? = nil) {
        self.text = text
        self.graphColorIndex = graphColorIndex
    }

    var displayText: String {
        if text.hasPrefix("HEAD -> ") {
            return String(text.dropFirst(8))
        }
        if text.hasPrefix("tag: ") {
            return String(text.dropFirst(5))
        }
        return text
    }

    var isTag: Bool {
        text.hasPrefix("tag: ")
    }

    var backgroundColor: Color {
        if isTag {
            return Color(nsColor: .systemPurple).opacity(0.15)
        }
        if let graphColorIndex {
            return GraphPalette.color(for: graphColorIndex).opacity(0.2)
        }
        return Color.accentColor.opacity(0.15)
    }

    var textColor: Color {
        if isTag {
            return Color(nsColor: .systemPurple)
        }
        if let graphColorIndex {
            return GraphPalette.color(for: graphColorIndex)
        }
        return .accentColor
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isTag ? "tag" : "arrow.triangle.branch")
                .font(.system(size: 8, weight: .semibold))

            Text(displayText)
                .font(.system(size: 9, weight: .semibold))
        }
            .lineLimit(1)
            .foregroundStyle(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}
