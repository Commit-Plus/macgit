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

final class CommitGraphRowSliceTests: XCTestCase {
    func testVerticalPathIsIncludedInEveryIntersectedRow() {
        let path = GraphPath(
            points: [
                CGPoint(x: 0, y: 0.5),
                CGPoint(x: 0, y: 2.5),
            ],
            colorIndex: 0,
            isHighlighted: true
        )

        let rows = CommitGraphRowSlice.makeRows(
            paths: [path],
            links: [],
            dots: [],
            rowCount: 3
        )

        XCTAssertEqual(rows.map(\.pathIndices), [[0], [0], [0]])
    }

    func testLinkAtRowBoundaryIsIncludedOnBothSides() {
        let link = GraphLink(
            start: CGPoint(x: 0, y: 0.5),
            control: CGPoint(x: 1, y: 0.5),
            end: CGPoint(x: 1, y: 1),
            colorIndex: 0,
            isHighlighted: true
        )

        let rows = CommitGraphRowSlice.makeRows(
            paths: [],
            links: [link],
            dots: [],
            rowCount: 2
        )

        XCTAssertEqual(rows.map(\.linkIndices), [[0], [0]])
    }

    func testDotsAreAssignedToTheirCommitRows() {
        let dots = (0..<3).map { row in
            GraphDot(
                center: CGPoint(x: 0, y: CGFloat(row) + 0.5),
                lane: 0,
                type: .default,
                colorIndex: row,
                isHighlighted: true
            )
        }

        let rows = CommitGraphRowSlice.makeRows(
            paths: [],
            links: [],
            dots: dots,
            rowCount: 3
        )

        XCTAssertEqual(rows.map(\.dotIndices), [[0], [1], [2]])
    }
}
