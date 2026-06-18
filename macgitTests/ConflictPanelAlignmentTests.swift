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
        XCTAssertEqual(panels.resultRows.map(\.lineNumber), [1, 2, 3, 4, 5, 6])

        XCTAssertFalse(panels.incomingRows[0].isPlaceholder)
        XCTAssertTrue(panels.incomingRows[3].isPlaceholder)
        XCTAssertTrue(panels.incomingRows[4].isPlaceholder)
        XCTAssertEqual(panels.incomingRows[3].text, "")
        XCTAssertEqual(panels.incomingRows[4].text, "")
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
