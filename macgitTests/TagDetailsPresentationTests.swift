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

final class TagDetailsPresentationTests: XCTestCase {
    func testPresentationExposesBasicTagAndCommitInformation() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-11T08:30:00Z"))
        let details = GitTagDetails(
            name: "v1.0.1",
            commitHash: "e3f1a9001b10694a6a473e7f7dc2294f5394864",
            authorName: "Thanh Tran",
            authorEmail: "trantienthanh2412@gmail.com",
            date: date,
            subject: "fix: improve image display logic",
            body: "and padding"
        )

        let presentation = TagDetailsPresentation(details: details)

        XCTAssertEqual(presentation.tagName, "v1.0.1")
        XCTAssertEqual(presentation.commitHash, details.commitHash)
        XCTAssertEqual(presentation.author, "Thanh Tran <trantienthanh2412@gmail.com>")
        XCTAssertFalse(presentation.date.isEmpty)
        XCTAssertEqual(presentation.message, "fix: improve image display logic\n\nand padding")
    }

    func testPresentationDoesNotAddBlankBodyBlockWhenBodyIsEmpty() {
        let details = GitTagDetails(
            name: "v1.0.1",
            commitHash: "abc123",
            authorName: "Thanh Tran",
            authorEmail: "trantienthanh2412@gmail.com",
            date: Date(timeIntervalSince1970: 0),
            subject: "Release",
            body: ""
        )

        XCTAssertEqual(TagDetailsPresentation(details: details).message, "Release")
    }
}
