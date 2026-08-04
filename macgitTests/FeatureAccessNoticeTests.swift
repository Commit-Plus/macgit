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

final class FeatureAccessNoticeTests: XCTestCase {
    func testProNoticeNamesTheBlockedFeature() {
        let notice = FeatureAccessNotice(feature: .pullRequests, denial: .requiresPro)

        XCTAssertEqual(notice.title, "Commit+ Pro Required")
        XCTAssertTrue(notice.message.contains("Pull Requests"))
    }

    func testVisibilityNoticeExplainsRetryableFailure() {
        let notice = FeatureAccessNotice(
            feature: .privateRepositories,
            denial: .repositoryVisibilityUnavailable
        )

        XCTAssertEqual(notice.title, "Repository Access Unavailable")
        XCTAssertTrue(notice.message.contains("try again"))
    }

    func testDisabledNoticeDoesNotSuggestUpgrade() {
        let notice = FeatureAccessNotice(feature: .pullRequests, denial: .featureDisabled)

        XCTAssertEqual(notice.title, "Feature Unavailable")
        XCTAssertFalse(notice.message.contains("Pro"))
    }
}
