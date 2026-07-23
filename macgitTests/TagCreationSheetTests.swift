//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
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

final class TagCreationSheetTests: XCTestCase {
    func testWorkingCopyParentUsesHeadAsCommitReference() {
        let request = TagCreationRequest(
            name: "v1.0.0",
            source: .workingCopyParent,
            pushRemote: nil
        )

        XCTAssertEqual(request.commitReference, "HEAD")
        XCTAssertTrue(TagCreationPolicy.canSubmit(name: request.name, source: request.source))
    }

    func testSpecifiedCommitIsRequiredAndPreserved() {
        let source = TagCommitSource.specified("abc123")
        let request = TagCreationRequest(name: "release", source: source, pushRemote: "origin")

        XCTAssertEqual(request.commitReference, "abc123")
        XCTAssertTrue(TagCreationPolicy.canSubmit(name: request.name, source: source))
        XCTAssertFalse(TagCreationPolicy.canSubmit(name: "release", source: .specified("  ")))
    }
}
