//
//  ConflictCodeView.swift
//  macgit
//

import SwiftUI

/// A read-only code view that shows line numbers and can highlight specific lines.
struct ConflictCodeView: View {
    static let defaultFontSize: CGFloat = 12
    static let verticalPadding: CGFloat = 8

    static func rowHeight(fontSize: CGFloat = defaultFontSize) -> CGFloat {
        fontSize + 6
    }

    let fileExtension: String
    let highlightColor: Color
    let fontSize: CGFloat
    let rows: [ConflictCodeLine]
    let selectionSide: ConflictPaneSelectionSide?
    let isSelected: (Int) -> Bool
    let onSelectionChanged: (Int, Bool) -> Void

    private var rowHeight: CGFloat {
        Self.rowHeight(fontSize: fontSize)
    }

    init(
        text: String,
        fileExtension: String,
        highlightedLines: Set<Int>,
        highlightColor: Color,
        fontSize: CGFloat = Self.defaultFontSize
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
        self.selectionSide = nil
        self.isSelected = { _ in false }
        self.onSelectionChanged = { _, _ in }
    }

    init(
        rows: [ConflictCodeLine],
        fileExtension: String,
        highlightColor: Color,
        fontSize: CGFloat = Self.defaultFontSize,
        selectionSide: ConflictPaneSelectionSide? = nil,
        isSelected: @escaping (Int) -> Bool = { _ in false },
        onSelectionChanged: @escaping (Int, Bool) -> Void = { _, _ in }
    ) {
        self.fileExtension = fileExtension
        self.highlightColor = highlightColor
        self.fontSize = fontSize
        self.rows = rows
        self.selectionSide = selectionSide
        self.isSelected = isSelected
        self.onSelectionChanged = onSelectionChanged
    }

    var body: some View {
        HStack(spacing: 0) {
            if selectionSide != nil {
                selectionControls
            }
            lineNumbers
            codeContent
        }
    }

    // MARK: - Selection Controls

    private var selectionControls: some View {
        VStack(alignment: .center, spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                selectionControl(for: row)
                    .frame(width: 28, height: rowHeight)
                    .background(rowBackground(for: row))
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .background(.secondary.opacity(0.05))
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
        .padding(.vertical, Self.verticalPadding)
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
        .padding(.vertical, Self.verticalPadding)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func selectionControl(for row: ConflictCodeLine) -> some View {
        if let selectionSide,
           let conflictSectionIndex = row.conflictSectionIndex,
           row.startsConflict {
            let selected = isSelected(conflictSectionIndex)

            Button(
                "\(selectionSide.title) conflict block",
                systemImage: selected ? "checkmark.square.fill" : "square"
            ) {
                onSelectionChanged(conflictSectionIndex, !selected)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .accessibilityValue(selected ? "Selected" : "Not selected")
        } else {
            Color.clear
        }
    }

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
