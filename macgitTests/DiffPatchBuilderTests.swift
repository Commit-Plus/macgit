import XCTest
@testable import macgit

final class DiffPatchBuilderTests: XCTestCase {
    func testWholeHunkPatchIncludesFileHeadersAndHunkLines() {
        let hunk = DiffHunk(
            header: "@@ -1,2 +1,2 @@",
            lines: [
                DiffLine(oldLineNumber: 1, newLineNumber: 1, text: "old", type: .removed),
                DiffLine(oldLineNumber: nil, newLineNumber: 1, text: "new", type: .added),
                DiffLine(oldLineNumber: 2, newLineNumber: 2, text: "same", type: .context)
            ]
        )

        let patch = DiffPatchBuilder.patchString(for: hunk, filePath: "Sources/App.swift")

        XCTAssertEqual(patch, """
        --- a/Sources/App.swift
        +++ b/Sources/App.swift
        @@ -1,2 +1,2 @@
        -old
        +new
         same

        """)
    }

    func testSelectedLinePatchRecomputesHeaderCounts() {
        let removed = DiffLine(oldLineNumber: 1, newLineNumber: nil, text: "remove me", type: .removed)
        let added = DiffLine(oldLineNumber: nil, newLineNumber: 1, text: "add me", type: .added)
        let ignored = DiffLine(oldLineNumber: 2, newLineNumber: 2, text: "ignore me", type: .added)
        let hunk = DiffHunk(
            header: "@@ -1,3 +1,3 @@",
            lines: [
                removed,
                DiffLine(oldLineNumber: 2, newLineNumber: 2, text: "context", type: .context),
                added,
                ignored
            ]
        )

        let patch = DiffPatchBuilder.patchString(
            for: hunk,
            selectedLines: [removed, added],
            filePath: "README.md"
        )

        XCTAssertEqual(patch, """
        --- a/README.md
        +++ b/README.md
        @@ -1,2 +1,2 @@
        -remove me
         context
        +add me

        """)
    }
}
