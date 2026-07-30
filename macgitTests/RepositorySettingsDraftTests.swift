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

final class RepositorySettingsDraftTests: XCTestCase {
    func testDraftPreservesSavedRemoteWhenRemotesAreUnavailable() {
        let draft = RepositorySettingsDraft(
            settings: RepoSettings(
                defaultRemoteName: "origin",
                defaultPullBranch: "main",
                pullStrategy: .merge,
                autoFetchOverride: false,
                refreshOnAppActiveOverride: true,
                confirmDetachedHeadCheckout: true,
                confirmDestructiveStashActions: true
            ),
            remotes: [],
            branches: ["main"],
            currentBranch: "main"
        )

        XCTAssertEqual(draft.selectedRemoteName, "origin")
    }

    func testDraftPrefersSavedBranchWhenItExistsInDetectedBranches() {
        let settings = RepoSettings(
            defaultRemoteName: "origin",
            defaultPullBranch: "release",
            pullStrategy: .merge,
            autoFetchOverride: false,
            refreshOnAppActiveOverride: true,
            confirmDetachedHeadCheckout: true,
            confirmDestructiveStashActions: true
        )

        let draft = RepositorySettingsDraft(
            settings: settings,
            remotes: ["origin", "upstream"],
            branches: ["main", "release"],
            currentBranch: "main"
        )

        XCTAssertEqual(draft.selectedRemoteName, "origin")
        XCTAssertEqual(draft.selectedBranchMode, .detected)
        XCTAssertEqual(draft.selectedDetectedBranch, "release")
        XCTAssertEqual(draft.manualBranchName, "")
    }

    func testDraftUsesCurrentBranchWhenSavedBranchIsManualAndDetectedBranchIsAvailable() {
        let draft = RepositorySettingsDraft(
            settings: RepoSettings(
                defaultRemoteName: "origin",
                defaultPullBranch: "release/hotfix",
                pullStrategy: .merge,
                autoFetchOverride: false,
                refreshOnAppActiveOverride: true,
                confirmDetachedHeadCheckout: true,
                confirmDestructiveStashActions: true
            ),
            remotes: ["origin"],
            branches: ["main", "develop"],
            currentBranch: "main"
        )

        XCTAssertEqual(draft.selectedBranchMode, .manual)
        XCTAssertEqual(draft.selectedDetectedBranch, "main")
        XCTAssertEqual(draft.manualBranchName, "release/hotfix")
    }

    func testDraftFallsBackToManualBranchEntryWhenSavedBranchIsCustom() {
        let draft = RepositorySettingsDraft(
            settings: RepoSettings(
                defaultRemoteName: "origin",
                defaultPullBranch: "release/hotfix",
                pullStrategy: .rebase,
                autoFetchOverride: true,
                refreshOnAppActiveOverride: false,
                confirmDetachedHeadCheckout: false,
                confirmDestructiveStashActions: false
            ),
            remotes: ["origin"],
            branches: ["main", "develop"],
            currentBranch: "main"
        )

        XCTAssertEqual(draft.selectedBranchMode, .manual)
        XCTAssertEqual(draft.manualBranchName, "release/hotfix")
        XCTAssertEqual(draft.resolvedSettings.defaultPullBranch, "release/hotfix")
        XCTAssertEqual(draft.resolvedSettings.pullStrategy, .rebase)
        XCTAssertEqual(draft.resolvedSettings.autoFetchOverride, true)
        XCTAssertEqual(draft.resolvedSettings.refreshOnAppActiveOverride, false)
    }

    func testDraftTrimsManualBranchNameOnSave() {
        var draft = RepositorySettingsDraft(
            settings: RepoSettings.defaults(currentBranch: "main", remotes: ["origin"]),
            remotes: ["origin"],
            branches: ["main"],
            currentBranch: "main"
        )
        draft.selectedBranchMode = .manual
        draft.manualBranchName = "  release/v2  "

        XCTAssertEqual(draft.resolvedSettings.defaultPullBranch, "release/v2")
    }

    func testDraftPreservesGlobalPullFetchInheritance() {
        let draft = RepositorySettingsDraft(
            settings: RepoSettings.defaults(currentBranch: "main", remotes: ["origin"]),
            remotes: ["origin"],
            branches: ["main"],
            currentBranch: "main"
        )

        XCTAssertNil(draft.autoFetchOverride)
        XCTAssertNil(draft.refreshOnAppActiveOverride)
        XCTAssertNil(draft.resolvedSettings.autoFetchOverride)
        XCTAssertNil(draft.resolvedSettings.refreshOnAppActiveOverride)
    }
}
