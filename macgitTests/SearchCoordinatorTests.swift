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

@MainActor
final class SearchCoordinatorTests: XCTestCase {
    func testSelectingTypeFiltersVisibleResults() {
        let coordinator = makeCoordinator()
        coordinator.results = makeResults()

        XCTAssertEqual(coordinator.filteredResults.count, 4)

        coordinator.selectFilter(.file)

        XCTAssertEqual(coordinator.filteredResults.count, 2)
        XCTAssertTrue(coordinator.filteredResults.allSatisfy { $0.type == .file })
        XCTAssertEqual(coordinator.selectedResultID, coordinator.filteredResults.first?.id)

        coordinator.selectFilter(.all)

        XCTAssertEqual(coordinator.filteredResults.count, 4)
    }

    func testKeyboardNavigationStaysInsideSelectedType() {
        let coordinator = makeCoordinator()
        coordinator.results = makeResults()
        coordinator.selectFilter(.file)
        let files = coordinator.filteredResults

        coordinator.selectNext()
        XCTAssertEqual(coordinator.selectedResultID, files[1].id)

        coordinator.selectNext()
        XCTAssertEqual(coordinator.selectedResultID, files[1].id)

        coordinator.selectPrevious()
        XCTAssertEqual(coordinator.selectedResultID, files[0].id)
        XCTAssertEqual(coordinator.selectedResult()?.type, .file)
    }

    private func makeCoordinator() -> SearchCoordinator {
        SearchCoordinator(repositoryURL: URL(fileURLWithPath: "/tmp"))
    }

    private func makeResults() -> [SearchResult] {
        [
            SearchResult(type: .commit, title: "Commit", subtitle: "abc1234", action: .showCommit("abc1234"), badge: nil),
            SearchResult(type: .file, title: "One.swift", subtitle: "macgit", action: .showFile("macgit/One.swift"), badge: nil),
            SearchResult(type: .file, title: "Two.swift", subtitle: "macgit", action: .showFile("macgit/Two.swift"), badge: nil),
            SearchResult(type: .branch, title: "main", subtitle: "Local", action: .checkoutBranch("main"), badge: nil)
        ]
    }
}
