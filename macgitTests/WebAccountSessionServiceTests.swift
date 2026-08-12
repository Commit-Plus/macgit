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

final class WebAccountSessionServiceTests: XCTestCase {
    func testProfileURLUsesConfiguredBaseURLAndFragmentToken() throws {
        let url = try WebAccountSignInURLBuilder.signInURL(
            baseURL: XCTUnwrap(URL(string: "http://localhost:3000")),
            customToken: "header.payload.signature",
            destination: .profile
        )

        XCTAssertEqual(
            url.absoluteString,
            "http://localhost:3000/session?next=/profile#token=header.payload.signature"
        )
    }

    func testPricingURLUsesAuthenticatedPricingDestination() throws {
        let url = try WebAccountSignInURLBuilder.signInURL(
            baseURL: XCTUnwrap(URL(string: "https://commit-plus.com")),
            customToken: "test-token",
            destination: .pricing
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://commit-plus.com/session?next=/pricing#token=test-token"
        )
    }

    func testDevicesURLUsesProfileDeviceSection() throws {
        let url = try WebAccountSignInURLBuilder.signInURL(
            baseURL: XCTUnwrap(URL(string: "https://commit-plus.com")),
            customToken: "test-token",
            destination: .devices
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://commit-plus.com/session?next=/profile?section%3Ddevices#token=test-token"
        )
    }
}
