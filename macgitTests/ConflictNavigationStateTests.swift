import XCTest
@testable import macgit

final class ConflictNavigationStateTests: XCTestCase {
    func testNavigationTargetsOnlyUnresolvedConflicts() {
        let document = ConflictResolutionDocument(
            sections: [
                .context("prefix\n"),
                .conflict(current: "current 1\n", incoming: "incoming 1\n"),
                .context("middle\n"),
                resolvedConflict(current: "current 2\n", incoming: "incoming 2\n"),
                .context("middle 2\n"),
                .conflict(current: "current 3\n", incoming: "incoming 3\n"),
            ],
            currentContent: "",
            incomingContent: ""
        )

        let navigation = ConflictNavigationState(document: document, currentSectionIndex: nil)

        XCTAssertEqual(navigation.unresolvedConflictSectionIndices, [1, 5])
        XCTAssertEqual(navigation.currentSectionIndex, 1)
        XCTAssertNil(navigation.previousSectionIndex)
        XCTAssertEqual(navigation.nextSectionIndex, 5)
        XCTAssertFalse(navigation.canNavigatePrevious)
        XCTAssertTrue(navigation.canNavigateNext)
    }

    func testNavigationSkipsResolvedCurrentConflict() {
        let document = ConflictResolutionDocument(
            sections: [
                .context("prefix\n"),
                .conflict(current: "current 1\n", incoming: "incoming 1\n"),
                resolvedConflict(current: "current 2\n", incoming: "incoming 2\n"),
                .conflict(current: "current 3\n", incoming: "incoming 3\n"),
            ],
            currentContent: "",
            incomingContent: ""
        )

        let navigation = ConflictNavigationState(document: document, currentSectionIndex: 2)

        XCTAssertEqual(navigation.currentSectionIndex, 3)
        XCTAssertEqual(navigation.previousSectionIndex, 1)
        XCTAssertNil(navigation.nextSectionIndex)
        XCTAssertTrue(navigation.canNavigatePrevious)
        XCTAssertFalse(navigation.canNavigateNext)
    }

    func testNavigationHasNoTargetsWhenAllConflictsAreResolved() {
        let document = ConflictResolutionDocument(
            sections: [
                resolvedConflict(current: "current 1\n", incoming: "incoming 1\n"),
                .context("middle\n"),
                resolvedConflict(current: "current 2\n", incoming: "incoming 2\n"),
            ],
            currentContent: "",
            incomingContent: ""
        )

        let navigation = ConflictNavigationState(document: document, currentSectionIndex: nil)

        XCTAssertTrue(navigation.unresolvedConflictSectionIndices.isEmpty)
        XCTAssertNil(navigation.currentSectionIndex)
        XCTAssertNil(navigation.previousSectionIndex)
        XCTAssertNil(navigation.nextSectionIndex)
        XCTAssertFalse(navigation.canNavigatePrevious)
        XCTAssertFalse(navigation.canNavigateNext)
    }

    private func resolvedConflict(current: String, incoming: String) -> ConflictResolutionSection {
        var section = ConflictResolutionSection.conflict(current: current, incoming: incoming)
        section.resolution = .incoming
        return section
    }
}
