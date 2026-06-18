//
//  ConflictCodeView.swift
//  macgit
//

import SwiftUI

/// A read-only code view that shows line numbers and can highlight specific lines.
struct ConflictCodeView: View {
    let fileExtension: String
    let highlightColor: Color
    let fontSize: CGFloat
    let rows: [ConflictCodeLine]

    private var rowHeight: CGFloat {
        fontSize + 6
    }

    init(
        text: String,
        fileExtension: String,
        highlightedLines: Set<Int>,
        highlightColor: Color,
        fontSize: CGFloat = 12
    ) {
        var components = text.components(separatedBy: "\n")
        if components.last == "" {
            components.removeLast()
        }

        self.fileExtension = fileExtension
        self.highlightColor = highlightColor
        self.fontSize = fontSize
        self.rows = components.enumerated().map { index, line in
            let lineNumber = index + 1
            return .actual(
                lineNumber: lineNumber,
                text: line,
                isConflict: highlightedLines.contains(lineNumber)
            )
        }
    }

    init(
        rows: [ConflictCodeLine],
        fileExtension: String,
        highlightColor: Color,
        fontSize: CGFloat = 12
    ) {
        self.fileExtension = fileExtension
        self.highlightColor = highlightColor
        self.fontSize = fontSize
        self.rows = rows
    }

    var body: some View {
        HStack(spacing: 0) {
            lineNumbers
            codeContent
        }
    }

    // MARK: - Line Numbers

    private var lineNumbers: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                Text(row.lineNumber.map(String.init) ?? "")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, 8)
                    .frame(height: rowHeight)
                    .background(rowBackground(for: row))
            }
        }
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.05))
    }

    // MARK: - Code Content

    private var codeContent: some View {
        let highlighter = SyntaxHighlighter(fileExtension: fileExtension)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                Text(attributedText(for: row, using: highlighter))
                    .font(.system(size: fontSize, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    .background(rowBackground(for: row))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func attributedText(
        for row: ConflictCodeLine,
        using highlighter: SyntaxHighlighter
    ) -> AttributedString {
        guard !row.isPlaceholder else { return AttributedString("") }
        return highlighter.attributedString(for: row.text, fontSize: fontSize)
    }

    @ViewBuilder
    private func rowBackground(for row: ConflictCodeLine) -> some View {
        if row.isPlaceholder {
            Color(nsColor: .separatorColor)
                .opacity(0.08)
                .overlay {
                    DiagonalHatchShape()
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
        } else if row.isConflict {
            highlightColor.opacity(0.2)
        } else {
            Color.clear
        }
    }
}
