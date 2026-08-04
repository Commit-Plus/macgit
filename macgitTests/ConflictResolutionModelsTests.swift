//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import XCTest
@testable import macgit

final class ConflictResolutionModelsTests: XCTestCase {
    func testConflictSectionsSplitCurrentIncomingAndContext() throws {
        let text = """
        intro
        <<<<<<< HEAD
        current line
        =======
        incoming line
        >>>>>>> feature
        outro
        """

        let document = try ConflictResolutionDocument.parse(text)

        XCTAssertEqual(document.sections.count, 3)
        XCTAssertEqual(document.sections[0].resolvedText, "intro\n")
        XCTAssertEqual(document.sections[1].currentText, "current line\n")
        XCTAssertEqual(document.sections[1].incomingText, "incoming line\n")
        XCTAssertEqual(document.sections[2].resolvedText, "outro")
    }

    func testConflictChoiceUpdatesResolvedOutput() throws {
        let text = """
        <<<<<<< HEAD
        current line
        =======
        incoming line
        >>>>>>> feature
        """

        var document = try ConflictResolutionDocument.parse(text)
        document.sections[0].resolution = .incoming

        XCTAssertEqual(document.resolvedText, "incoming line\n")
    }

    func testConflictManualEditOverridesPresetChoice() throws {
        let text = """
        <<<<<<< HEAD
        alpha
        =======
        beta
        >>>>>>> branch
        """

        var document = try ConflictResolutionDocument.parse(text)
        document.sections[0].manualResult = "alpha\nbeta"

        XCTAssertEqual(document.sections[0].resolvedText, "alpha\nbeta")
        XCTAssertEqual(document.resolvedText, "alpha\nbeta")
    }

    func testWholeResultManualEditOverridesGeneratedDocument() throws {
        let text = """
        prefix
        <<<<<<< HEAD
        current
        =======
        incoming
        >>>>>>> branch
        suffix
        """

        var document = try ConflictResolutionDocument.parse(text)
        document.sections[1].resolution = .both
        document.manualResolvedText = "prefix\ncustom result\nsuffix"

        XCTAssertEqual(document.resolvedText, "prefix\ncustom result\nsuffix")
        XCTAssertEqual(
            ConflictNavigationState(document: document, currentSectionIndex: nil).remainingCount,
            0
        )
    }

    func testSelectingAResolutionClearsWholeResultManualEdit() throws {
        let text = """
        <<<<<<< HEAD
        current
        =======
        incoming
        >>>>>>> branch
        """

        var document = try ConflictResolutionDocument.parse(text)
        document.manualResolvedText = "custom\n"

        document.selectAllConflicts(.incoming)

        XCTAssertNil(document.manualResolvedText)
        XCTAssertEqual(document.resolvedText, "incoming\n")
    }

    func testResultHighlightsInsertedAndChangedLines() {
        let baseline = "first\nold\nlast"
        let result = "first\nnew\nlast\nadded"

        XCTAssertEqual(
            ConflictResultLineHighlights.changedLineIndices(result: result, baseline: baseline),
            [1, 3]
        )
    }

    func testResultHighlightsBlankLines() {
        XCTAssertEqual(
            ConflictResultLineHighlights.blankLineIndices(in: "first\n\n   \nlast"),
            [1, 2]
        )
    }

    func testConflictSelectionCanUseCurrentIncomingOrBoth() {
        var section = ConflictResolutionSection.conflict(
            current: "current\n",
            incoming: "incoming\n"
        )

        XCTAssertFalse(section.isCurrentSelected)
        XCTAssertFalse(section.isIncomingSelected)
        XCTAssertEqual(section.resolution, .manual)
        XCTAssertEqual(section.resolvedText, "")

        section.setCurrentSelected(true)

        XCTAssertTrue(section.isCurrentSelected)
        XCTAssertFalse(section.isIncomingSelected)
        XCTAssertEqual(section.resolution, .current)
        XCTAssertEqual(section.resolvedText, "current\n")

        section.setIncomingSelected(true)

        XCTAssertTrue(section.isCurrentSelected)
        XCTAssertTrue(section.isIncomingSelected)
        XCTAssertEqual(section.resolution, .both)
        XCTAssertEqual(section.resolvedText, "current\nincoming\n")

        section.setCurrentSelected(false)

        XCTAssertFalse(section.isCurrentSelected)
        XCTAssertTrue(section.isIncomingSelected)
        XCTAssertEqual(section.resolution, .incoming)
        XCTAssertEqual(section.resolvedText, "incoming\n")

        section.setCurrentSelected(true)
        section.setIncomingSelected(false)

        XCTAssertTrue(section.isCurrentSelected)
        XCTAssertFalse(section.isIncomingSelected)
        XCTAssertEqual(section.resolution, .current)
        XCTAssertEqual(section.resolvedText, "current\n")
    }

    func testConflictSelectionCanClearBothSides() {
        var section = ConflictResolutionSection.conflict(
            current: "current\n",
            incoming: "incoming\n"
        )

        section.setCurrentSelected(false)

        XCTAssertFalse(section.isCurrentSelected)
        XCTAssertFalse(section.isIncomingSelected)
        XCTAssertEqual(section.resolution, .manual)
        XCTAssertEqual(section.resolvedText, "")
    }

    func testDocumentCanSelectIncomingForEveryConflict() {
        var second = ConflictResolutionSection.conflict(
            current: "second current\n",
            incoming: "second incoming\n"
        )
        second.resolution = .both

        var document = ConflictResolutionDocument(
            sections: [
                .context("prefix\n"),
                .conflict(current: "first current\n", incoming: "first incoming\n"),
                second,
            ],
            currentContent: "",
            incomingContent: ""
        )

        document.selectAllConflicts(.incoming)

        XCTAssertTrue(document.allConflictsUse(.incoming))
        XCTAssertFalse(document.allConflictsUse(.current))
        XCTAssertEqual(document.sections[1].resolution, .incoming)
        XCTAssertEqual(document.sections[2].resolution, .incoming)
        XCTAssertEqual(document.resolvedText, "prefix\nfirst incoming\nsecond incoming\n")
    }

    func testDocumentCanSelectCurrentForEveryConflict() {
        var first = ConflictResolutionSection.conflict(
            current: "first current\n",
            incoming: "first incoming\n"
        )
        first.resolution = .incoming

        var document = ConflictResolutionDocument(
            sections: [
                first,
                .conflict(current: "second current\n", incoming: "second incoming\n"),
            ],
            currentContent: "",
            incomingContent: ""
        )

        document.selectAllConflicts(.current)

        XCTAssertTrue(document.allConflictsUse(.current))
        XCTAssertFalse(document.allConflictsUse(.incoming))
        XCTAssertEqual(document.sections[0].resolution, .current)
        XCTAssertEqual(document.sections[1].resolution, .current)
        XCTAssertEqual(document.resolvedText, "first current\nsecond current\n")
    }

    func testDocumentCanToggleIncomingForEveryConflictWithoutClearingCurrent() {
        var first = ConflictResolutionSection.conflict(
            current: "first current\n",
            incoming: "first incoming\n"
        )
        first.resolution = .current

        var second = ConflictResolutionSection.conflict(
            current: "second current\n",
            incoming: "second incoming\n"
        )
        second.resolution = .both

        var document = ConflictResolutionDocument(
            sections: [first, second],
            currentContent: "",
            incomingContent: ""
        )

        document.setAllConflictsSelected(true, for: .incoming)

        XCTAssertTrue(document.allConflictsSelect(.incoming))
        XCTAssertEqual(document.sections[0].resolution, .both)
        XCTAssertEqual(document.sections[1].resolution, .both)

        document.setAllConflictsSelected(false, for: .incoming)

        XCTAssertFalse(document.allConflictsSelect(.incoming))
        XCTAssertTrue(document.allConflictsSelect(.current))
        XCTAssertEqual(document.sections[0].resolution, .current)
        XCTAssertEqual(document.sections[1].resolution, .current)
    }

    func testConflictCanTakeBothInEitherOrder() {
        var section = ConflictResolutionSection.conflict(
            current: "current\n",
            incoming: "incoming\n"
        )

        section.resolution = .bothIncomingFirst
        XCTAssertTrue(section.isIncomingSelected)
        XCTAssertTrue(section.isCurrentSelected)
        XCTAssertEqual(section.resolvedText, "incoming\ncurrent\n")

        section.resolution = .both
        XCTAssertEqual(section.resolvedText, "current\nincoming\n")
    }
}
