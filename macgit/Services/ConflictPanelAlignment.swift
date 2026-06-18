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

        for section in document.sections {
            let incomingLines = Self.lines(of: section.incomingPaneText)
            let currentLines = Self.lines(of: section.currentPaneText)
            let resultLines = Self.lines(of: section.resolvedText)
            let alignedLineCount = max(incomingLines.count, currentLines.count, resultLines.count)

            incomingRows += incomingBuilder.rows(
                from: incomingLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict
            )
            currentRows += currentBuilder.rows(
                from: currentLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict
            )
            resultRows += resultBuilder.rows(
                from: resultLines,
                alignedLineCount: alignedLineCount,
                isConflict: section.isConflict
            )
        }

        self.incomingRows = incomingRows
        self.currentRows = currentRows
        self.resultRows = resultRows
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
        isConflict: Bool
    ) -> [ConflictCodeLine] {
        guard alignedLineCount > 0 else { return [] }

        return (0..<alignedLineCount).map { index in
            guard index < lines.count else {
                return .placeholder(isConflict: isConflict)
            }

            defer { nextLineNumber += 1 }
            return .actual(
                lineNumber: nextLineNumber,
                text: lines[index],
                isConflict: isConflict
            )
        }
    }
}
