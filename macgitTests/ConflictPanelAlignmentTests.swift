import XCTest
@testable import macgit

final class ConflictPanelAlignmentTests: XCTestCase {
    func testShorterConflictSideReceivesUnnumberedPlaceholderRows() {
        let document = ConflictResolutionDocument(
            sections: [
                .context("prefix 1\nprefix 2\n"),
                .conflict(
                    current: "current 1\ncurrent 2\ncurrent 3\n",
                    incoming: "incoming 1\n"
                ),
                .context("suffix\n"),
            ],
            currentContent: "",
            incomingContent: ""
        )

        let panels = ConflictPanelAlignment(document: document)

        XCTAssertEqual(panels.currentRows.map(\.lineNumber), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(panels.incomingRows.map(\.lineNumber), [1, 2, 3, nil, nil, 4])
        XCTAssertEqual(panels.resultRows.map(\.lineNumber), [1, 2, nil, nil, nil, 3])

        XCTAssertFalse(panels.incomingRows[0].isPlaceholder)
        XCTAssertTrue(panels.incomingRows[3].isPlaceholder)
        XCTAssertTrue(panels.incomingRows[4].isPlaceholder)
        XCTAssertEqual(panels.incomingRows[3].text, "")
        XCTAssertEqual(panels.incomingRows[4].text, "")
        XCTAssertFalse(panels.currentRows[0].startsConflict)
        XCTAssertTrue(panels.currentRows[2].startsConflict)
        XCTAssertEqual(panels.currentRows[2].conflictSectionIndex, 1)
        XCTAssertTrue(panels.incomingRows[2].startsConflict)
        XCTAssertEqual(panels.incomingRows[2].conflictSectionIndex, 1)
        XCTAssertFalse(panels.currentRows[3].startsConflict)
        XCTAssertEqual(panels.rowIndex(forConflictSectionIndex: 1), 2)
        XCTAssertNil(panels.rowIndex(forConflictSectionIndex: 0))
    }

    func testResultPaneParticipatesInAlignmentWhenItHasMostRows() {
        var conflict = ConflictResolutionSection.conflict(
            current: "current\n",
            incoming: "incoming 1\nincoming 2\n"
        )
        conflict.resolution = .both

        let document = ConflictResolutionDocument(
            sections: [conflict],
            currentContent: "",
            incomingContent: ""
        )

        let panels = ConflictPanelAlignment(document: document)

        XCTAssertEqual(panels.currentRows.map(\.lineNumber), [1, nil, nil])
        XCTAssertEqual(panels.incomingRows.map(\.lineNumber), [1, 2, nil])
        XCTAssertEqual(panels.resultRows.map(\.lineNumber), [1, 2, 3])

        XCTAssertTrue(panels.currentRows[1].isPlaceholder)
        XCTAssertTrue(panels.currentRows[2].isPlaceholder)
        XCTAssertTrue(panels.incomingRows[2].isPlaceholder)
    }
}
