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

final class SearchFileOpenerTests: XCTestCase {
    func testVisualStudioCodeTakesPriorityOverOtherInstalledEditors() {
        let installed = applicationURLs(for: [
            "com.jetbrains.intellij", "com.microsoft.VSCode", "com.apple.dt.Xcode"
        ])

        let applications = SearchFileApplicationResolver.availableApplications {
            installed[$0]
        }

        XCTAssertEqual(applications.first?.bundleIdentifier, "com.microsoft.VSCode")
    }

    func testIntelliJIsUsedWhenVisualStudioCodeIsNotInstalled() {
        let installed = applicationURLs(for: ["com.jetbrains.intellij", "com.apple.dt.Xcode"])

        let applications = SearchFileApplicationResolver.availableApplications {
            installed[$0]
        }

        XCTAssertEqual(applications.first?.bundleIdentifier, "com.jetbrains.intellij")
    }

    func testOnlyInstalledApplicationsAreReturnedIncludingPreview() {
        let installed = applicationURLs(for: ["dev.zed.Zed", "com.apple.Preview"])

        let applications = SearchFileApplicationResolver.availableApplications {
            installed[$0]
        }

        XCTAssertEqual(applications.map(\.bundleIdentifier), ["dev.zed.Zed", "com.apple.Preview"])
    }

    private func applicationURLs(for bundleIdentifiers: [String]) -> [String: URL] {
        Dictionary(uniqueKeysWithValues: bundleIdentifiers.map { identifier in
            (identifier, URL(fileURLWithPath: "/Applications/\(identifier).app"))
        })
    }
}
