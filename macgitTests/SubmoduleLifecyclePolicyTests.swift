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

final class SubmoduleLifecyclePolicyTests: XCTestCase {
    func testEditSettingsIsAllowedForEveryDiscoveredEntry() {
        for state in [
            GitSubmoduleState.clean,
            .modified,
            .newCommits,
            .uninitialized,
            .missing,
            .conflict
        ] {
            XCTAssertEqual(
                SubmoduleLifecyclePolicy.decision(for: .editSettings, entry: entry(state: state)),
                SubmoduleLifecycleDecision(
                    isAllowed: true,
                    requiresConfirmation: false,
                    message: nil
                )
            )
        }
    }

    func testCleanInitializedEntryAllowsConfirmedLifecycleActions() {
        let entry = entry(state: .clean)

        XCTAssertEqual(
            SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: false), entry: entry),
            SubmoduleLifecycleDecision(
                isAllowed: true,
                requiresConfirmation: true,
                message: "Deinitialize removes local checkout files. The .gitmodules entry and recorded gitlink remain."
            )
        )
        XCTAssertEqual(
            SubmoduleLifecyclePolicy.decision(for: .remove(force: false), entry: entry),
            SubmoduleLifecycleDecision(
                isAllowed: true,
                requiresConfirmation: true,
                message: "Remove Submodule stages the path and .gitmodules entry for removal."
            )
        )
    }

    func testDirtyInitializedEntryRequiresExplicitForce() {
        let entry = entry(state: .modified)

        for action in [
            SubmoduleLifecycleAction.deinitialize(force: false),
            .remove(force: false)
        ] {
            XCTAssertEqual(
                SubmoduleLifecyclePolicy.decision(for: action, entry: entry),
                SubmoduleLifecycleDecision(
                    isAllowed: false,
                    requiresConfirmation: true,
                    message: "This submodule has uncommitted changes. Confirm force to continue."
                )
            )
        }

        XCTAssertTrue(
            SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: true), entry: entry).isAllowed
        )
        XCTAssertTrue(
            SubmoduleLifecyclePolicy.decision(for: .remove(force: true), entry: entry).isAllowed
        )
    }

    func testUninitializedEntryCannotDeinitializeButCanBeRemoved() {
        let entry = entry(state: .uninitialized)

        XCTAssertEqual(
            SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: false), entry: entry),
            SubmoduleLifecycleDecision(
                isAllowed: false,
                requiresConfirmation: false,
                message: "This submodule has no local checkout to deinitialize."
            )
        )
        XCTAssertEqual(
            SubmoduleLifecyclePolicy.decision(for: .remove(force: false), entry: entry),
            SubmoduleLifecycleDecision(
                isAllowed: true,
                requiresConfirmation: true,
                message: "Remove Submodule stages the path and .gitmodules entry for removal."
            )
        )
    }

    func testMissingEntryCannotDeinitializeButCanBeRemoved() {
        let entry = entry(state: .missing)

        XCTAssertEqual(
            SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: false), entry: entry),
            SubmoduleLifecycleDecision(
                isAllowed: false,
                requiresConfirmation: false,
                message: "This submodule has no local checkout to deinitialize."
            )
        )
        XCTAssertEqual(
            SubmoduleLifecyclePolicy.decision(for: .remove(force: false), entry: entry),
            SubmoduleLifecycleDecision(
                isAllowed: true,
                requiresConfirmation: true,
                message: "Remove Submodule stages the path and .gitmodules entry for removal."
            )
        )
    }

    func testConflictEntryRequiresExplicitForce() {
        let entry = entry(state: .conflict)

        for action in [
            SubmoduleLifecycleAction.deinitialize(force: false),
            .remove(force: false)
        ] {
            XCTAssertEqual(
                SubmoduleLifecyclePolicy.decision(for: action, entry: entry),
                SubmoduleLifecycleDecision(
                    isAllowed: false,
                    requiresConfirmation: true,
                    message: "This submodule has uncommitted changes. Confirm force to continue."
                )
            )
        }

        XCTAssertTrue(
            SubmoduleLifecyclePolicy.decision(for: .deinitialize(force: true), entry: entry).isAllowed
        )
        XCTAssertTrue(
            SubmoduleLifecyclePolicy.decision(for: .remove(force: true), entry: entry).isAllowed
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
