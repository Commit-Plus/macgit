import FirebaseFirestore
import XCTest
@testable import macgit

final class EntitlementDocumentDecoderTests: XCTestCase {
    func testValidActiveProDocumentDecodesAllFields() {
        let periodEnd = Date(timeIntervalSince1970: 1_800_000_000)
        let entitlement = EntitlementDocumentDecoder.decode([
            "plan": "pro",
            "access": "active",
            "billingStatus": "active",
            "source": "admin_test",
            "currentPeriodEnd": Timestamp(date: periodEnd),
            "cancelAtPeriodEnd": true
        ])

        XCTAssertEqual(
            entitlement,
            AccountEntitlement(
                plan: .pro,
                access: .active,
                billingStatus: .active,
                source: .adminTest,
                currentPeriodEnd: periodEnd,
                cancelAtPeriodEnd: true
            )
        )
    }

    func testMissingDocumentDefaultsToFree() {
        XCTAssertEqual(EntitlementDocumentDecoder.decode(nil), .free)
    }

    func testMalformedDocumentDefaultsToFreeAndReportsDiagnostic() {
        var diagnostics: [String] = []

        let entitlement = EntitlementDocumentDecoder.decode(
            ["plan": "enterprise", "access": 1, "billingStatus": true],
            onDiagnostic: { diagnostics.append($0) }
        )

        XCTAssertEqual(entitlement, .free)
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertFalse(diagnostics[0].isEmpty)
    }
}
+//
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

