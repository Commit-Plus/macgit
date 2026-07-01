//
//  RepositoryOperationProgressTests.swift
//  macgitTests
//

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
final class RepositoryOperationProgressTests: XCTestCase {
    func testBeginAndEndTracksActiveOperation() {
        let progress = RepositoryOperationProgress()
        let id = progress.begin(message: "Fetching remotes...")

        XCTAssertEqual(progress.activeOperation?.id, id)
        XCTAssertEqual(progress.activeOperation?.message, "Fetching remotes...")
        XCTAssertEqual(progress.activeOperation?.canCancel, true)

        progress.end(id)

        XCTAssertNil(progress.activeOperation)
    }

    func testRunClearsOperationAfterCompletion() async {
        let progress = RepositoryOperationProgress()
        let operationRan = expectation(description: "operation ran")

        progress.run(message: "Pushing branches...") {
            operationRan.fulfill()
        }

        XCTAssertEqual(progress.activeOperation?.message, "Pushing branches...")

        await fulfillment(of: [operationRan], timeout: 1)
        await Task.yield()

        XCTAssertNil(progress.activeOperation)
    }

    func testCancelMarksOperationAndCancelsTask() async {
        let progress = RepositoryOperationProgress()
        let taskCancelled = expectation(description: "task cancelled")

        progress.run(message: "Pulling changes...") {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            taskCancelled.fulfill()
        }

        progress.cancelActiveOperation()

        XCTAssertEqual(progress.activeOperation?.isCancelling, true)

        await fulfillment(of: [taskCancelled], timeout: 1)
        await Task.yield()

        XCTAssertNil(progress.activeOperation)
    }
}
