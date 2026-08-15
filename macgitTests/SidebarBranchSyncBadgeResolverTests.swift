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

final class SidebarBranchSyncBadgeResolverTests: XCTestCase {
    func testCurrentBranchPrefersFallbackStatus() {
        let resolved = SidebarBranchSyncBadgeResolver.status(
            for: "main",
            currentBranch: "main",
            branchSyncStatus: ["main": BranchSyncStatus(ahead: 0, behind: 0)],
            currentBranchFallbackSyncStatus: BranchSyncStatus(ahead: 2, behind: 1)
        )

        XCTAssertEqual(resolved, BranchSyncStatus(ahead: 2, behind: 1))
    }

    func testCurrentBranchPrefersZeroToolbarStatusOverStaleCachedStatus() {
        let resolved = SidebarBranchSyncBadgeResolver.status(
            for: "main",
            currentBranch: "main",
            branchSyncStatus: ["main": BranchSyncStatus(ahead: 1, behind: 0)],
            currentBranchFallbackSyncStatus: BranchSyncStatus(ahead: 0, behind: 0)
        )

        XCTAssertEqual(resolved, BranchSyncStatus(ahead: 0, behind: 0))
    }

    func testCurrentBranchFallsBackToCachedStatusWhenToolbarStatusMissing() {
        let resolved = SidebarBranchSyncBadgeResolver.status(
            for: "main",
            currentBranch: "main",
            branchSyncStatus: ["main": BranchSyncStatus(ahead: 1, behind: 0)],
            currentBranchFallbackSyncStatus: nil
        )

        XCTAssertEqual(resolved, BranchSyncStatus(ahead: 1, behind: 0))
    }

    func testNonCurrentBranchUsesCachedStatus() {
        let resolved = SidebarBranchSyncBadgeResolver.status(
            for: "feature/demo",
            currentBranch: "main",
            branchSyncStatus: ["feature/demo": BranchSyncStatus(ahead: 3, behind: 0)],
            currentBranchFallbackSyncStatus: BranchSyncStatus(ahead: 1, behind: 0)
        )

        XCTAssertEqual(resolved, BranchSyncStatus(ahead: 3, behind: 0))
    }
}
