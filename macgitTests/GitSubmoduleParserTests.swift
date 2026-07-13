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

final class GitSubmoduleParserTests: XCTestCase {
    private let recordedCommit = String(repeating: "1", count: 40)
    private let checkedOutCommit = String(repeating: "2", count: 40)

    func testParsesInitializedCleanSubmodule() throws {
        let entries = try parse(statusPrefix: " ", statusCommit: recordedCommit)

        XCTAssertEqual(entries, [
            GitSubmoduleEntry(
                name: "SharedKit",
                path: "Packages/SharedKit",
                url: "../SharedKit.git",
                branch: "main",
                recordedCommit: recordedCommit,
                checkedOutCommit: recordedCommit,
                state: .clean
            )
        ])
        XCTAssertTrue(entries[0].isInitialized)
    }

    func testParsesUninitializedSubmodule() throws {
        let entries = try parse(statusPrefix: "-", statusCommit: recordedCommit)

        XCTAssertEqual(entries[0].state, .uninitialized)
        XCTAssertNil(entries[0].checkedOutCommit)
        XCTAssertFalse(entries[0].isInitialized)
    }

    func testParsesDifferentCheckedOutCommitAsNewCommits() throws {
        let entries = try parse(statusPrefix: "+", statusCommit: checkedOutCommit)

        XCTAssertEqual(entries[0].state, .newCommits)
        XCTAssertEqual(entries[0].recordedCommit, recordedCommit)
        XCTAssertEqual(entries[0].checkedOutCommit, checkedOutCommit)
    }

    func testParsesConflictState() throws {
        let entries = try parse(statusPrefix: "U", statusCommit: checkedOutCommit)

        XCTAssertEqual(entries[0].state, .conflict)
        XCTAssertEqual(entries[0].checkedOutCommit, checkedOutCommit)
    }

    func testConfiguredEntryMissingFromStatusIsMissing() throws {
        let entries = try GitSubmoduleParser.parse(
            config: configFixture(),
            index: indexFixture(),
            status: ""
        )

        XCTAssertEqual(entries[0].state, .missing)
        XCTAssertNil(entries[0].checkedOutCommit)
    }

    func testPreservesRelativeURLBranchAndNestedPath() throws {
        let entries = try parse(statusPrefix: " ", statusCommit: recordedCommit)

        XCTAssertEqual(entries[0].name, "SharedKit")
        XCTAssertEqual(entries[0].path, "Packages/SharedKit")
        XCTAssertEqual(entries[0].url, "../SharedKit.git")
        XCTAssertEqual(entries[0].branch, "main")
        XCTAssertEqual(entries[0].id, "Packages/SharedKit")
    }

    func testOmitsIncompleteConfigurationWhileKeepingValidSibling() throws {
        let config = configFixture()
            + "submodule.MissingURL.path\nPackages/MissingURL\0"
            + "submodule.MissingPath.url\n../MissingPath.git\0"

        let entries = try GitSubmoduleParser.parse(
            config: config,
            index: indexFixture(),
            status: statusFixture(prefix: " ", commit: recordedCommit)
        )

        XCTAssertEqual(entries.map(\.name), ["SharedKit"])
    }

    func testParsesSubmoduleNameContainingDotsAndPathContainingSpaces() throws {
        let config = "submodule.shared.ui.path\nPackages/Shared UI\0"
            + "submodule.shared.ui.url\n../SharedUI.git\0"
        let index = "160000 \(recordedCommit) 0\tPackages/Shared UI\n"
        let status = " \(recordedCommit) Packages/Shared UI (heads/main)\n"

        let entries = try GitSubmoduleParser.parse(config: config, index: index, status: status)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "shared.ui")
        XCTAssertEqual(entries[0].path, "Packages/Shared UI")
        XCTAssertEqual(entries[0].state, .clean)
    }

    private func parse(statusPrefix: Character, statusCommit: String) throws -> [GitSubmoduleEntry] {
        try GitSubmoduleParser.parse(
            config: configFixture(),
            index: indexFixture(),
            status: statusFixture(prefix: statusPrefix, commit: statusCommit)
        )
    }

    private func configFixture() -> String {
        "submodule.SharedKit.path\nPackages/SharedKit\0"
            + "submodule.SharedKit.url\n../SharedKit.git\0"
            + "submodule.SharedKit.branch\nmain\0"
    }

    private func indexFixture() -> String {
        "160000 \(recordedCommit) 0\tPackages/SharedKit\n"
    }

    private func statusFixture(prefix: Character, commit: String) -> String {
        "\(prefix)\(commit) Packages/SharedKit (heads/main)\n"
    }
}
