import Foundation

struct ConflictCodeLine: Equatable {
    let lineNumber: Int?
    let text: String
    let isConflict: Bool
    let isPlaceholder: Bool

    static func actual(lineNumber: Int, text: String, isConflict: Bool) -> ConflictCodeLine {
        ConflictCodeLine(
            lineNumber: lineNumber,
            text: text,
            isConflict: isConflict,
            isPlaceholder: false
        )
    }

    static func placeholder(isConflict: Bool) -> ConflictCodeLine {
        ConflictCodeLine(
            lineNumber: nil,
            text: "",
            isConflict: isConflict,
            isPlaceholder: true
        )
    }
}
