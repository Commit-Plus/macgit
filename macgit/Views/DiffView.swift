//
//  DiffView.swift
//  macgit
//

import SwiftUI

struct DiffView: View {
    let hunks: [DiffHunk]

    var body: some View {
        if hunks.isEmpty {
            EmptyStateView(message: "No diff to display", detail: "Select a file to see changes")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hunks) { hunk in
                        HunkView(hunk: hunk)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

struct HunkView: View {
    let hunk: DiffHunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.1))

            ForEach(hunk.lines) { line in
                DiffLineView(line: line)
            }
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine

    var backgroundColor: Color {
        switch line.type {
        case .added:
            return Color.green.opacity(0.12)
        case .removed:
            return Color.red.opacity(0.12)
        case .context:
            return Color.clear
        case .header:
            return Color.clear
        }
    }

    var textColor: Color {
        switch line.type {
        case .added:
            return Color.green.opacity(0.9)
        case .removed:
            return Color.red.opacity(0.9)
        case .context:
            return .primary
        case .header:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Old line number
            Text(line.oldLineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            // New line number
            Text(line.newLineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 8)

            // Content
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }
}
