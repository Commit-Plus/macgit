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

import FirebaseFirestore
import XCTest
@testable import macgit

final class CloudSettingsDocumentTests: XCTestCase {
    private let snapshot = AppSettingsSnapshot(
        showToolbarButtonText: false,
        showSubmodules: true,
        showSubtrees: false,
        showHeaderBranchButton: true,
        showHeaderMergeButton: false,
        showHeaderStashButton: true,
        showHeaderRemoteButton: false,
        showHeaderFinderButton: true,
        showHeaderTerminalButton: false
    )

    func testEncodingUsesExactDocumentSchema() throws {
        let timestamp = Timestamp(date: Date(timeIntervalSince1970: 123))

        let document = CloudSettingsDocument.encode(snapshot, updatedAt: timestamp)

        XCTAssertEqual(
            Set(document.keys),
            [
                "schemaVersion",
                "showToolbarButtonText",
                "showSubmodules",
                "showSubtrees",
                "showHeaderBranchButton",
                "showHeaderMergeButton",
                "showHeaderStashButton",
                "showHeaderRemoteButton",
                "showHeaderFinderButton",
                "showHeaderTerminalButton",
                "updatedAt"
            ]
        )
        XCTAssertEqual(document["schemaVersion"] as? Int, 1)
        XCTAssertEqual(document["showToolbarButtonText"] as? Bool, false)
        XCTAssertEqual(document["showSubmodules"] as? Bool, true)
        XCTAssertEqual(document["showSubtrees"] as? Bool, false)
        XCTAssertEqual(document["showHeaderBranchButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderMergeButton"] as? Bool, false)
        XCTAssertEqual(document["showHeaderStashButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderRemoteButton"] as? Bool, false)
        XCTAssertEqual(document["showHeaderFinderButton"] as? Bool, true)
        XCTAssertEqual(document["showHeaderTerminalButton"] as? Bool, false)
        XCTAssertEqual(document["updatedAt"] as? Timestamp, timestamp)
    }

    func testDecodingDefaultsMissingHeaderButtonsToTrue() throws {
        var document = validDocument()
        document.removeValue(forKey: "showHeaderBranchButton")
        document.removeValue(forKey: "showHeaderRemoteButton")

        let decoded = try CloudSettingsDocument.decode(document)

        XCTAssertTrue(decoded.showHeaderBranchButton)
        XCTAssertTrue(decoded.showHeaderRemoteButton)
    }

    func testDecodingValidDocumentReturnsCompleteSnapshot() throws {
        let decoded = try CloudSettingsDocument.decode(validDocument())

        XCTAssertEqual(decoded, snapshot)
    }

    func testDecodingRejectsMissingRequiredField() {
        var document = validDocument()
        document.removeValue(forKey: "showSubmodules")

        XCTAssertThrowsError(try CloudSettingsDocument.decode(document)) { error in
            XCTAssertEqual(error as? CloudSettingsError, .invalidDocument)
        }
    }

    func testDecodingRejectsWrongFieldTypeWithoutPartialSnapshot() {
        var document = validDocument()
        document["showSubtrees"] = "false"

        XCTAssertThrowsError(try CloudSettingsDocument.decode(document)) { error in
            XCTAssertEqual(error as? CloudSettingsError, .invalidDocument)
        }
    }

    func testDecodingRejectsMissingOrWrongTimestamp() {
        var missing = validDocument()
        missing.removeValue(forKey: "updatedAt")
        var wrongType = validDocument()
        wrongType["updatedAt"] = Date()

        XCTAssertThrowsError(try CloudSettingsDocument.decode(missing))
        XCTAssertThrowsError(try CloudSettingsDocument.decode(wrongType))
    }

    private func validDocument() -> [String: Any] {
        CloudSettingsDocument.encode(
            snapshot,
            updatedAt: Timestamp(date: Date(timeIntervalSince1970: 123))
        )
    }
}
