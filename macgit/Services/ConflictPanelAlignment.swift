import Foundation

struct ConflictPanelAlignment {
    let incomingRows: [ConflictCodeLine]
    let currentRows: [ConflictCodeLine]
    let resultRows: [ConflictCodeLine]

    init(document: ConflictResolutionDocument) {
        var incomingBuilder = PaneLineBuilder()
        var currentBuilder = PaneLineBuilder()
        var resultBuilder = PaneLineBuilder()

        var incomingRows: [ConflictCodeLine] = []
        var currentRows: [ConflictCodeLine] = []
        var resultRows: [ConflictCodeLine] = []

        for (sectionIndex, section) in document.sections.enumerated() {
            let incomingLines = Self.lines(of: section.incomingPaneText)
            let currentLines = Self.lines(of: section.currentPaneText)
            let resultLines = Self.lines(of: section.resolvedText)
            let alignedLineCount = max(incomingLines.count, currentLines.count, resultLines.count)
            let conflictSectionIndex = section.isConflict ? sectionIndex : nil

            incomingRows += incomingBuilder.rows(
                from: incomingLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict,
                conflictSectionIndex: conflictSectionIndex
            )
            currentRows += currentBuilder.rows(
                from: currentLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict,
                conflictSectionIndex: conflictSectionIndex
            )
            resultRows += resultBuilder.rows(
                from: resultLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict,
                conflictSectionIndex: conflictSectionIndex
            )
        }

        self.incomingRows = incomingRows
        self.currentRows = currentRows
        self.resultRows = resultRows
    }

    func rowIndex(forConflictSectionIndex sectionIndex: Int) -> Int? {
        incomingRows.firstIndex { row in
            row.startsConflict && row.conflictSectionIndex == sectionIndex
        }
    }

    private static func lines(of text: String) -> [String] {
        var components = text.components(separatedBy: "\n")
        if components.last == "" {
            components.removeLast()
        }
        return components
    }
}

private struct PaneLineBuilder {
    private var nextLineNumber = 1

    mutating func rows(
        from lines: [String],
        alignedLineCount: Int,
        isConflict: Bool,
        conflictSectionIndex: Int?
    ) -> [ConflictCodeLine] {
        guard alignedLineCount > 0 else { return [] }

        return (0..<alignedLineCount).map { index in
            let startsConflict = index == 0 && isConflict

            guard index < lines.count else {
                return .placeholder(
                    isConflict: isConflict,
                    conflictSectionIndex: conflictSectionIndex,
                    startsConflict: startsConflict
                )
            }

            defer { nextLineNumber += 1 }
            return .actual(
                lineNumber: nextLineNumber,
                text: lines[index],
                isConflict: isConflict,
                conflictSectionIndex: conflictSectionIndex,
                startsConflict: startsConflict
            )
        }
    }
}
