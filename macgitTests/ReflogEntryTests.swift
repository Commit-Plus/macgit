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

final class ReflogEntryTests: XCTestCase {
    func testEventDateAndActorComeFromReflog() throws {
        let output = "abc\0HEAD@{2026-09-08T10:20:30+07:00}\0Operator\0operator@example.com\0reset: moving to HEAD~1"
        let entry = try XCTUnwrap(ReflogEntry.parse(output).first)
        XCTAssertEqual(entry.reference, "HEAD")
        XCTAssertEqual(entry.actor, "Operator")
        XCTAssertEqual(entry.action, "reset")
        XCTAssertEqual(entry.date, ISO8601DateFormatter().date(from: "2026-09-08T03:20:30Z"))
        XCTAssertEqual(entry.displayCommitMessage, "reset: moving to HEAD~1")
    }

    func testFullCommitMessagePreservesLineBreaks() throws {
        let output = "abc\0HEAD@{2026-09-08T10:20:30+07:00}\0Operator\0operator@example.com\0commit: feat: subject\0feat: subject\n\nBody line one\nBody line two\n\u{1e}"
        let entry = try XCTUnwrap(ReflogEntry.parse(output).first)
        XCTAssertEqual(entry.message, "commit: feat: subject")
        XCTAssertEqual(entry.commitMessage, "feat: subject\n\nBody line one\nBody line two")
        XCTAssertEqual(entry.displayCommitMessage, "feat: subject\n\nBody line one\nBody line two")
    }

    func testRepeatedEventsRemainDistinctAndStableWhenNewEventsArrive() {
        let event = "abc\0refs/heads/main@{2026-09-08T10:20:30+07:00}\0A\0a@example.com\0commit: hello"
        let original = ReflogEntry.parse(event + "\n" + event)
        XCTAssertEqual(Set(original.map(\.id)).count, 2)
        let refreshed = ReflogEntry.parse(event.replacingOccurrences(of: "abc", with: "def") + "\n" + event + "\n" + event)
        XCTAssertEqual(Array(refreshed.dropFirst()), original)
    }

    func testIdenticalEventsAcrossPagesKeepDistinctIDs() {
        let event = "abc\0HEAD@{2026-09-08T10:20:30+07:00}\0A\0a@example.com\0reset: moving to HEAD"
        let firstPage = ReflogEntry.parse(Array(repeating: event, count: 30).joined(separator: "\n"))
        let nextPage = ReflogEntry.parse(Array(repeating: event, count: 30).joined(separator: "\n"))
        let combined = ReflogEntry.appending(nextPage, to: firstPage)
        XCTAssertEqual(combined.count, 60)
        XCTAssertEqual(Set(combined.map(\.id)).count, 60)
        XCTAssertEqual(Array(combined.prefix(30)), firstPage)
    }

    func testEmptyAndMalformedRecords() {
        XCTAssertTrue(ReflogEntry.parse("").isEmpty)
        XCTAssertTrue(ReflogEntry.parse("bad\nabc\0HEAD\0A\0email\0event").isEmpty)
    }
}
