//
//  CommitRowView.swift
//  macgit
//

import SwiftUI

struct CommitRowView: View {
    let commit: Commit
    let graphWidth: CGFloat
    let isSelected: Bool
    let isDragActive: Bool
    let messageWidth: CGFloat
    let authorWidth: CGFloat
    let dateWidth: CGFloat
    let commitWidth: CGFloat

    private var authorText: String {
        "\(commit.author) <\(commit.email)>"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Fixed-width spacer so all commit messages align regardless of lane count
            Color.clear
                .frame(width: graphWidth, height: 24)
                .fixedSize()

            // Message + ref labels (share the message column width)
            HStack(spacing: 4) {
                Text(commit.message)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !commit.refs.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(commit.refs.prefix(3), id: \.self) { ref in
                            RefLabel(text: ref)
                        }
                    }
                }
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
    }
}

struct RefLabel: View {
    let text: String

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
        isTag ? Color(nsColor: .systemPurple).opacity(0.15) : Color.accentColor.opacity(0.15)
    }

    var textColor: Color {
        isTag ? Color(nsColor: .systemPurple) : .accentColor
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}
