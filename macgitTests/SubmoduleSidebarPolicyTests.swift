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

final class SubmoduleSidebarPolicyTests: XCTestCase {
    func testInitializedExistingStatesExposeReadOnlyActions() {
        let expected: Set<SubmoduleSidebarAction> = [
            .openInCommitPlus,
            .showInFinder,
            .openInTerminal
        ]

        for state in [
            GitSubmoduleState.clean,
            .modified,
            .newCommits,
            .conflict
        ] {
            XCTAssertEqual(
                SubmoduleSidebarPolicy.actions(for: entry(state: state)),
                expected,
                "Unexpected actions for \(state)"
            )
        }
    }

    func testUninitializedAndMissingStatesExposeNoReadOnlyActions() {
        XCTAssertEqual(
            SubmoduleSidebarPolicy.actions(for: entry(state: .uninitialized)),
            []
        )
        XCTAssertEqual(
            SubmoduleSidebarPolicy.actions(for: entry(state: .missing)),
            []
        )
    }

    private func entry(state: GitSubmoduleState) -> GitSubmoduleEntry {
        GitSubmoduleEntry(
            name: "SharedKit",
            path: "Packages/SharedKit",
            url: "../SharedKit.git",
            branch: "main",
            recordedCommit: String(repeating: "1", count: 40),
            checkedOutCommit: state == .uninitialized || state == .missing
                ? nil
                : String(repeating: "1", count: 40),
            state: state
        )
    }
}
